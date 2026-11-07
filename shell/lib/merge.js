.pragma library

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function clone(value) {
    if (Array.isArray(value))
        return value.map(clone);
    if (isPlainObject(value)) {
        const copy = {};
        for (const key in value)
            copy[key] = clone(value[key]);
        return copy;
    }
    return value;
}

function merge(defaults, user) {
    const base = isPlainObject(defaults) ? defaults : {};
    const out = clone(base);

    if (!isPlainObject(user))
        return out;

    for (const key in user) {
        const next = user[key];
        if (next === undefined)
            continue;

        if (!(key in base)) {
            out[key] = clone(next);
            continue;
        }

        const current = base[key];
        if (isPlainObject(current) && isPlainObject(next)) {
            out[key] = merge(current, next);
        } else if (Array.isArray(current) && Array.isArray(next)) {
            out[key] = clone(next);
        } else if (current === null && next === null) {
            out[key] = null;
        } else if (current !== null && next !== null && typeof current === typeof next) {
            out[key] = next;
        }
    }

    return out;
}
