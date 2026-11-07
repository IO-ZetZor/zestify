.pragma library

/**
 * Advances a damped spring by dt from offset x0 (value minus target) and velocity v0; returns [x, v].
 */
function step(x0, v0, w, z, dt) {
    if (z < 1) {
        const wd = w * Math.sqrt(1 - z * z);
        const e = Math.exp(-z * w * dt);
        const c = Math.cos(wd * dt);
        const s = Math.sin(wd * dt);
        const b = (v0 + z * w * x0) / wd;
        return [e * (x0 * c + b * s), e * (c * (b * wd - z * w * x0) - s * (x0 * wd + z * w * b))];
    }
    if (z === 1) {
        const ec = Math.exp(-w * dt);
        const bc = v0 + w * x0;
        return [(x0 + bc * dt) * ec, (bc - w * (x0 + bc * dt)) * ec];
    }
    const r = Math.sqrt(z * z - 1);
    const r1 = -w * (z - r);
    const r2 = -w * (z + r);
    const c1 = (v0 - r2 * x0) / (r1 - r2);
    const c2 = x0 - c1;
    const e1 = Math.exp(r1 * dt);
    const e2 = Math.exp(r2 * dt);
    return [c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2];
}
