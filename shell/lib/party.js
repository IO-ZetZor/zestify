.pragma library

function clamp01(value) {
    const number = Number(value);
    if (!Number.isFinite(number))
        return 0;
    return Math.max(0, Math.min(1, number));
}

function lerp(from, to, progress) {
    return from + (to - from) * progress;
}

function morphRect(progress, from, to) {
    const t = clamp01(progress);
    return {
        x: lerp(from.x, to.x, t),
        y: lerp(from.y, to.y, t),
        width: lerp(from.width, to.width, t),
        height: lerp(from.height, to.height, t)
    };
}

function phase(progress, start, end) {
    return clamp01((progress - start) / (end - start));
}

function smooth(progress) {
    const t = clamp01(progress);
    return t * t * (3 - 2 * t);
}

// Anticipate, descend and unfold, then settle the slight overshoot. Entry is
// linear time; each channel gets its own easing rather than easing it twice.
function formationRect(progress, from, to) {
    const t = clamp01(progress);
    const squeeze = Math.sin(phase(t, 0, 0.25) * Math.PI);
    const travel = smooth(phase(t, 0.12, 0.78));
    const unfold = smooth(phase(t, 0.20, 0.78));
    const settle = 1 - smooth(phase(t, 0.78, 1));
    const width = lerp(from.width * (1 - 0.045 * squeeze), to.width, travel)
        + to.width * 0.025 * unfold * settle;
    const height = lerp(from.height * (1 - 0.12 * squeeze), to.height, unfold)
        + to.height * 0.025 * unfold * settle;
    const centerX = lerp(from.x + from.width / 2, to.x + to.width / 2, travel);
    const centerY = lerp(from.y + from.height / 2, to.y + to.height / 2, travel)
        + to.height * 0.018 * travel * settle;
    return { x: centerX - width / 2, y: centerY - height / 2,
             width: width, height: height };
}

function toggleOwner(owner, screenName) {
    if (!screenName)
        return owner || "";
    return owner === screenName ? "" : screenName;
}

function closeOwner(owner, screenName) {
    if (!screenName || owner === screenName)
        return "";
    return owner || "";
}

function isOn(owner, screenName) {
    return !!owner && !!screenName && owner === screenName;
}

// Cava stereo raw output is mirrored: [left high..low, right low..high].
// Take the central bass bins, retaining impacts on either stereo channel.
// Weight the peak as well as the mean: kicks need not fill the whole band.
function bass(levels, count) {
    if (!levels || levels.length === 0)
        return 0;
    if (levels.length === 1)
        return clamp01(levels[0]);
    const half = Math.floor(levels.length / 2);
    const size = Math.max(1, Math.min(count || 5, half));
    let left = 0;
    let right = 0;
    let leftPeak = 0;
    let rightPeak = 0;
    for (let i = 0; i < size; i++) {
        const l = clamp01(levels[half - 1 - i]);
        const r = clamp01(levels[half + i]);
        left += l;
        right += r;
        leftPeak = Math.max(leftPeak, l);
        rightPeak = Math.max(rightPeak, r);
    }
    return Math.max(0.7 * leftPeak + 0.3 * left / size,
                    0.7 * rightPeak + 0.3 * right / size);
}

// SuperFlux-style neighbour comparison rejects energy moving between nearby
// frequencies. Require net band growth too: a pitch jump is not a drum impact.
function bassFlux(levels, previous) {
    if (!levels || !previous || levels.length !== previous.length || levels.length < 2)
        return 0;
    const half = Math.floor(levels.length / 2);
    const size = Math.min(5, half);
    let sum = 0;
    let peak = 0;
    let energy = 0;
    let oldEnergy = 0;
    for (let i = 0; i < size; ++i) {
        const current = Math.max(clamp01(levels[half - 1 - i]), clamp01(levels[half + i]));
        const old = Math.max(clamp01(previous[half - 1 - i]), clamp01(previous[half + i]));
        let neighbour = old;
        for (let j = Math.max(0, i - 1); j <= Math.min(size - 1, i + 1); ++j)
            neighbour = Math.max(neighbour, clamp01(previous[half - 1 - j]), clamp01(previous[half + j]));
        const rise = Math.max(0, current - neighbour);
        energy += current;
        oldEnergy += old;
        sum += rise;
        peak = Math.max(peak, rise);
    }
    const growth = Math.max(0, energy - oldEnergy);
    // A weaker kick can add energy next to a held stronger note, where the
    // neighbour maximum masks its flux. Net growth retains that addition.
    return Math.min(Math.max(0.7 * peak + 0.3 * sum / size, 0.7 * growth / size), growth);
}

function median(values) {
    if (!values.length)
        return 0;
    const ordered = values.slice().sort((a, b) => a - b);
    const middle = Math.floor(ordered.length / 2);
    return ordered.length % 2 ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2;
}

function idleAnalysis() {
    return { previous: [], history: [], previousFlux: 0, peakFlux: 0,
             armed: true, trough: 0, previousBass: 0, age: 10000 };
}

// Only fixed-gain, unsmoothed bins enter this detector. Display normalization
// cannot turn a quiet accent into a strong one or turn gain drift into a beat.
function advanceAnalysis(state, levels, dtMs) {
    const elapsed = Number(dtMs);
    const dt = Number.isFinite(elapsed) ? Math.max(0, elapsed) : 0;
    const old = dt > 450 ? idleAnalysis() : (state || idleAnalysis());
    const rawBass = bass(levels);
    const previous = old.previous.length ? old.previous : Array(levels.length).fill(0);
    const flux = bassFlux(levels, previous);
    const center = median(old.history);
    const deviation = median(old.history.map(value => Math.abs(value - center)));
    const mean = old.history.length ? old.history.reduce((a, b) => a + b, 0) / old.history.length : 0;
    const threshold = Math.max(0.00006, center + 2.5 * deviation + mean * 0.2);
    const relative = flux / Math.max(0.0001, rawBass);
    const armed = old.armed || flux < old.peakFlux * 0.5;
    const candidate = armed && rawBass > 0.00015 && flux > threshold
        && relative >= 0.045 && flux > old.previousFlux * 1.03;
    const onset = candidate && old.age + dt >= 40;
    const trough = rawBass < old.previousBass ? Math.min(old.trough, rawBass) : old.trough;
    return { previous: levels.slice(), history: old.history.slice(-15).concat([flux]),
             previousFlux: flux, peakFlux: candidate ? flux : Math.max(old.peakFlux, flux),
             armed: candidate ? false : armed, previousBass: rawBass,
             trough: candidate ? rawBass : trough, age: onset ? 0 : old.age + dt,
             onset: onset, dt: dt, rawBass: rawBass,
             level: clamp01(rawBass / 0.25),
             contrast: clamp01(Math.max(flux, rawBass - trough) / 0.25),
             confidence: clamp01(flux / Math.max(0.00006, threshold * 3)) * clamp01(relative / 0.25) };
}

function idleImpact() {
    return { baseline: 0, slowBaseline: 0, buildup: 0,
             previous: 0, peak: 0, trough: 0, riseAge: 0,
             armed: true, cooldown: 0, sampleAge: 0,
             fluxPrevious: 0, fluxPeak: 0, fluxTrough: 0, fluxBaseline: 0, fluxArmed: true,
             age: 10000, sourceAge: 10000, gap: 10000,
             intervals: [], interval: 600, sequence: 0, intrinsicStrength: 0,
             strength: 0, contrast: 0, origin: 0, damping: 1, attackOpen: false, fluxHit: false,
             release: 150, hold: 24, tail: 0, tailRelease: 150,
             envelope: 0, hit: false };
}

function impactStrength(level, contrast) {
    // Fixed-gain level and contrast retain quiet accents on sustained bass.
    return clamp01(Math.pow(clamp01(level), 1.2)
        * Math.pow(clamp01(contrast) / Math.max(0.001, level), 0.6));
}

function pulseEnvelope(strength, age, hold, release) {
    const value = strength * Math.exp(-Math.max(0, age - hold) / release);
    return value < 0.001 ? 0 : value;
}

// Fresh audio detects trough-to-peak rises; render ticks only advance time.
// Follow the first 120ms of an attack instead of assigning every onset the same
// punch. A rolling median of real onset intervals adapts the release to rolls,
// double-time passages and tempo changes without inventing beats in silence.
function advanceImpact(state, level, dtMs, enabled, threshold, freshSample, fluxLevel, analysis) {
    if (!enabled)
        return idleImpact();
    const elapsed = Number(dtMs);
    const dt = Number.isFinite(elapsed) ? Math.max(0, elapsed) : 0;
    let old = state || idleImpact();
    const value = clamp01(level);
    const gate = Number.isFinite(threshold) ? clamp01(threshold) : 0.62;
    const sampled = freshSample !== false;
    const sampleAge = old.sampleAge + dt;
    // A suspended shell or stalled stream has no trustworthy tempo/history.
    if (sampled && sampleAge > 450)
        old = idleImpact();
    const sampleDt = analysis && Number.isFinite(analysis.dt) ? Math.max(0, analysis.dt)
        : Math.max(1, old.sampleAge + dt);
    const sourceAge = sampled ? old.sourceAge + sampleDt : old.sourceAge;
    const live = sampled || sampleAge <= 250;
    const baseline = live ? lerp(old.baseline, sampled ? value : old.previous,
        1 - Math.exp(-dt / 240)) : old.baseline * Math.exp(-dt / 180);
    const slowBaseline = lerp(old.slowBaseline, baseline, 1 - Math.exp(-dt / 2200));
    const buildupTarget = live ? clamp01((baseline - slowBaseline - 0.06) * 2.5) : 0;
    const buildup = lerp(old.buildup, buildupTarget,
        1 - Math.exp(-dt / (buildupTarget > old.buildup ? 380 : 280)));
    const cooldown = Math.max(0, old.cooldown - dt);
    const armed = old.armed || (sampled
        && old.peak - value > Math.max(0.025, old.peak * 0.06));
    const trough = sampled ? (armed ? Math.min(old.trough, value) : value) : old.trough;
    const rising = sampled && value > old.previous;
    const riseAge = sampled ? (rising ? old.riseAge + sampleDt : 0) : old.riseAge;
    const contrast = Math.max(0, value - trough);
    const scalarCandidate = analysis ? sampled && analysis.onset : sampled && armed && value >= gate * 0.2
        && contrast >= Math.max(0.035, old.baseline * 0.08)
        && rising && contrast / Math.max(16, riseAge) >= 0.00045;
    // The whole-band response may arrive after a kick was already found in
    // one frequency bin. Consume that delayed rise without a second punch.
    const delayedScalar = scalarCandidate && old.fluxHit
        && sourceAge < Math.min(80, old.interval * 0.4);
    const scalarOnset = scalarCandidate && !delayedScalar;
    const flux = sampled ? clamp01(fluxLevel) : old.fluxPrevious;
    const fluxArmed = old.fluxArmed || (sampled
        && old.fluxPeak - flux > Math.max(0.008, old.fluxPeak * 0.22));
    const fluxTrough = sampled ? (fluxArmed ? Math.min(old.fluxTrough, flux) : flux)
        : old.fluxTrough;
    // Require a separate burst after the attack's initial 60ms. This catches
    // overlapping kicks without counting every rising bin in one attack twice.
    const fluxOnset = !analysis && sampled && fluxArmed && value >= gate * 0.2
        && flux >= Math.max(0.028, old.fluxBaseline * 0.9 + 0.018)
        && flux - fluxTrough >= Math.max(0.018, old.fluxBaseline * 0.65)
        && flux > old.fluxPrevious;
    const onset = scalarOnset || (fluxOnset && sourceAge >= Math.min(60, old.interval * 0.25));
    const consumed = onset || delayedScalar;
    const hit = sourceAge >= 40 && onset;
    const age = hit ? 0 : old.age + dt;
    let intervals = old.intervals;
    let interval = old.interval;
    if (hit) {
        const gap = sourceAge;
        if (gap > 1800) {
            intervals = [];
            interval = 600;
        } else if (gap >= 40) {
            intervals = old.intervals.slice(-4).concat([gap]);
            const sorted = intervals.slice().sort((a, b) => a - b);
            interval = sorted[Math.floor(sorted.length / 2)];
        }
    }
    const damping = hit ? 0.58 + 0.42 * smooth(phase(interval, 60, 320)) : old.damping;
    const release = hit ? Math.max(38, Math.min(150, interval * 0.26)) : old.release;
    const hold = hit ? Math.max(8, Math.min(24, interval * 0.09)) : old.hold;
    const hitContrast = analysis ? Math.min(value, analysis.contrast)
        : scalarOnset ? contrast : Math.min(value, Math.max(flux * 4, value - old.previous));
    const origin = hit ? Math.max(0, value - hitContrast) : old.origin;
    const followsAttack = sampled && old.attackOpen && !consumed && rising && sourceAge <= 120;
    const attackContrast = hit ? hitContrast : old.contrast;
    const strength = hit ? impactStrength(value, hitContrast) * damping
        : followsAttack ? Math.max(old.strength,
            impactStrength(value, Math.max(attackContrast, value - origin)) * damping)
        : old.strength;
    const intrinsicStrength = hit ? impactStrength(value, hitContrast)
        : followsAttack ? Math.max(old.intrinsicStrength,
            impactStrength(value, Math.max(attackContrast, value - origin))) : old.intrinsicStrength;
    // Keep the previous release alive when a weaker hit arrives. It can decay,
    // but cannot stack, restart the heavy hit or snap the camera backwards.
    const previousEnvelope = Math.max(old.tail * Math.exp(-dt / old.tailRelease),
        pulseEnvelope(old.strength, old.age + dt, old.hold, old.release));
    const tailRelease = hit ? Math.min(old.release, release) : old.tailRelease;
    const tail = hit ? previousEnvelope : old.tail * Math.exp(-dt / tailRelease);
    const envelope = Math.max(tail, pulseEnvelope(strength, age, hold, release));
    return {
        baseline: baseline, slowBaseline: slowBaseline,
        buildup: buildup,
        previous: sampled ? value : old.previous,
        peak: consumed ? value : (sampled && !armed ? Math.max(old.peak, value) : old.peak),
        trough: consumed ? value : trough, riseAge: consumed ? 0 : riseAge,
        fluxPrevious: flux,
        fluxPeak: fluxOnset ? flux : (sampled && !fluxArmed ? Math.max(old.fluxPeak, flux) : old.fluxPeak),
        fluxTrough: fluxOnset ? flux : fluxTrough,
        fluxArmed: fluxOnset ? false : fluxArmed,
        fluxBaseline: sampled ? lerp(old.fluxBaseline, flux, 1 - Math.exp(-sampleDt / 180)) : old.fluxBaseline,
        // Consume duplicate onsets during cooldown so they cannot land late.
        armed: consumed ? false : armed,
        cooldown: hit ? 40 : cooldown, sampleAge: sampled ? 0 : sampleAge,
        age: age, sourceAge: hit ? 0 : sourceAge, gap: hit ? sourceAge : old.gap,
        intervals: intervals, interval: interval, intrinsicStrength: intrinsicStrength,
        sequence: old.sequence + (hit ? 1 : 0),
        strength: strength, contrast: attackContrast, origin: origin, damping: damping,
        attackOpen: hit || (old.attackOpen && age <= 120 && !consumed
            && (!sampled || value >= old.previous)),
        fluxHit: hit ? !scalarOnset : old.fluxHit,
        release: release, hold: hold, tail: tail < 0.001 ? 0 : tail, tailRelease: tailRelease,
        envelope: envelope < 0.001 ? 0 : envelope,
        hit: hit
    };
}

function idleRhythm() {
    return { time: 0, history: [], period: 600, confidence: 0, lastLandmarkTime: -1 };
}

// Rhythm uses salient attacks and their repeating pattern, not the median of
// every detected note/subdivision. It never generates impacts on predicted beats.
function advanceRhythm(state, impact, dt) {
    const old = state || idleRhythm();
    dt = Number.isFinite(dt) ? Math.max(0, dt) : 0;
    const time = old.time + dt;
    const history = old.history.filter(event => time - event.time < 8000).map(event => ({
        time: event.time, weight: event.weight, sequence: event.sequence }));
    if (impact.hit)
        history.push({time: time, weight: impact.intrinsicStrength, sequence: impact.sequence});
    else if (history.length && history[history.length - 1].sequence === impact.sequence)
        history[history.length - 1].weight = Math.max(history[history.length - 1].weight, impact.intrinsicStrength);
    const recent = history.slice(-64);
    const weights = recent.map(event => event.weight).sort((a, b) => b - a);
    const salience = Math.max(0.12, (weights[Math.floor(weights.length * 0.2)] || 0) * 0.55);
    const strong = [];
    for (const event of recent.filter(event => event.weight >= salience)) {
        const previous = strong[strong.length - 1];
        // Several transients can belong to one kick or a short fill. Keep them
        // for impacts, but collect their salience into one rhythm landmark.
        if (previous && event.time - previous.time < 180)
            previous.weight = Math.max(previous.weight, event.weight);
        else
            strong.push({time: event.time, weight: event.weight});
    }
    let period = old.period;
    const latestLandmark = strong.length ? strong[strong.length - 1].time : -1;
    const recentRhythm = latestLandmark >= 0 && time - latestLandmark <= period * 1.8;
    let confidence = old.confidence * Math.exp(-dt / (recentRhythm ? 8000 : 1200));
    const newLandmark = latestLandmark > old.lastLandmarkTime;
    if (newLandmark && strong.length >= 4 && time - latestLandmark < 1400) {
        const landmarks = strong.slice(-12);
        const gaps = [];
        for (let i = 1; i < landmarks.length; ++i)
            gaps.push(landmarks[i].time - landmarks[i - 1].time);
        const candidates = gaps.filter(gap => gap >= 240 && gap <= 1200);
        let best = 0;
        let bestPeriod = period;
        const latest = gaps.slice(-3);
        const latestPeriod = median(latest);
        const coherent = latest.length === 3 && latestPeriod >= 240 && latestPeriod <= 1200
            && latest.every(gap => Math.abs(gap - latestPeriod) < latestPeriod * 0.12);
        for (const candidate of candidates) {
            let score = 0;
            for (const gap of gaps) {
                const multiple = Math.max(1, Math.round(gap / candidate));
                const error = Math.abs(gap - candidate * multiple) / candidate;
                score += Math.max(0, 1 - error / 0.18) / multiple;
            }
            score /= gaps.length;
            if (score > best) { best = score; bestPeriod = candidate; }
        }
        if (coherent) {
            if (Math.abs(latestPeriod - period) > period * 0.12) {
                period = latestPeriod;
                confidence *= 0.5;
            } else {
                period = lerp(period, latestPeriod, 0.2);
            }
            confidence = lerp(confidence, 1, 0.25);
        } else if (best > 0.6) {
            if (old.confidence <= 0.5 || Math.abs(bestPeriod - period) < period * 0.12) {
                period = Math.abs(bestPeriod - period) < period * 0.12 ? lerp(period, bestPeriod, 0.2) : bestPeriod;
                confidence = lerp(confidence, best, 0.25);
            }
        }
    }
    return { time: time, history: recent, period: period, confidence: confidence,
             lastLandmarkTime: Math.max(old.lastLandmarkTime, latestLandmark) };
}

// A brief damped recoil rather than continuous jitter on a held bass note.
function impactShake(state) {
    const amount = Math.pow(state.strength, 1.3) * Math.exp(-state.age / 65);
    const t = state.age / 1000;
    const seed = state.sequence * 2.39996;
    return { x: Math.sin(t * 65 + seed) * amount,
             y: Math.sin(t * 83 + seed * 1.7) * amount * 0.65,
             rotation: Math.sin(t * 52 + seed * 0.7) * amount };
}

function idleCamera() {
    return { envelope: 0, x: 0, y: 0, rotation: 0, density: 0 };
}

// Isolated hits land sharply. Dense audio updates a continuous camera target,
// with longer easing and very little directional recoil during drum rolls.
function advanceCamera(state, impact, previousAge, dtMs, rhythm) {
    const old = state || idleCamera();
    const elapsed = Number(dtMs);
    const dt = Number.isFinite(elapsed) ? Math.max(0, elapsed) : 0;
    const gap = impact.hit ? impact.gap : previousAge + dt;
    // React to the first quick follow-up even before the tempo median catches
    // up. Retain that protection through uneven spacing, then ease it away.
    const recentInterval = impact.hit ? Math.min(gap, impact.interval) : impact.interval;
    const intervalDensity = 1 - smooth(phase(recentInterval, 100, 320));
    const targetDensity = impact.age < 320
        ? Math.max(intervalDensity, impact.hit ? 0 : old.density) : 0;
    const density = targetDensity >= old.density ? targetDensity
        : lerp(old.density, targetDensity, 1 - Math.exp(-dt / 420));
    const isolated = impact.hit && gap >= 280 && density < 0.2 && old.density < 0.2;
    const tau = old.envelope < impact.envelope
        ? lerp(12, 65, density) : lerp(24, 90, density);
    const targetEnvelope = lerp(old.envelope,
        impact.envelope, 1 - Math.exp(-dt / tau));
    // Cap travel per millisecond as well as easing it: a much stronger beat
    // inside a roll must not cause a one-frame jump, even at uneven cadence.
    const travel = dt * lerp(0.012, 0.002, smooth(phase(density, 0.2, 0.8)));
    const envelope = isolated ? impact.envelope : old.envelope
        + Math.max(-travel, Math.min(travel, targetEnvelope - old.envelope));
    const recoil = impactShake(impact);
    const gain = (1 - 0.9 * density) * (rhythm ? 0.65 + 0.35 * rhythm.confidence : 1);
    const alpha = isolated ? 1 : 1 - Math.exp(-dt / lerp(18, 65, density));
    const recoilTravel = dt * lerp(0.03, 0.0015, smooth(phase(density, 0.2, 0.8)));
    function blendRecoil(from, to) {
        const change = (to - from) * alpha;
        return from + (isolated ? change
            : Math.max(-recoilTravel, Math.min(recoilTravel, change)));
    }
    return { envelope: envelope < 0.001 ? 0 : envelope,
             x: blendRecoil(old.x, recoil.x * gain),
             y: blendRecoil(old.y, recoil.y * gain),
             rotation: blendRecoil(old.rotation, recoil.rotation * gain), density: density };
}

// Background colour follows its own slow exposure, with no onset-frame flash.
function advanceTint(state, target, dtMs) {
    const dt = Number.isFinite(dtMs) ? Math.max(0, dtMs) : 0;
    const old = clamp01(state);
    const value = clamp01(target);
    const change = (value - old) * (1 - Math.exp(-dt / (value > old ? 90 : 240)));
    const travel = dt * 0.002;
    const result = old + Math.max(-travel, Math.min(travel, change));
    return result < 0.001 ? 0 : result;
}

// Map a bar index onto an arbitrary-length smoothed level array.
function sampleLevel(levels, index, count) {
    if (!levels || levels.length === 0)
        return 0;
    if (levels.length === 1 || count <= 1)
        return clamp01(levels[0]);
    const position = Math.max(0, Math.min(count - 1, index))
        * (levels.length - 1) / (count - 1);
    const lower = Math.floor(position);
    const upper = Math.min(levels.length - 1, lower + 1);
    return clamp01(lerp(clamp01(levels[lower]), clamp01(levels[upper]),
                         position - lower));
}

// Deterministic, zero-mean shake offsets in the -1..1 range.
function shake(energy, time, seed) {
    const amount = clamp01(energy);
    const phase = Number(seed) || 0;
    const t = Number(time) || 0;
    return {
        x: Math.sin(t * 12.7 + phase * 1.7) * amount,
        y: Math.sin(t * 15.3 + phase * 2.3 + 1.1) * amount,
        rotation: Math.sin(t * 8.9 + phase * 0.9 + 2.7) * amount
    };
}
