.pragma library

function getValue(data, path, fallback) {
    let node = data;
    const parts = String(path).split(".");
    for (let i = 0; i < parts.length; i++) {
        if (node === null || node === undefined || typeof node !== "object")
            return fallback;
        if (node[parts[i]] === undefined)
            return fallback;
        node = node[parts[i]];
    }
    return node === undefined ? fallback : node;
}

function setValue(data, path, value) {
    const parts = String(path).split(".");
    let node = data;
    for (let i = 0; i < parts.length - 1; i++) {
        const key = parts[i];
        if (node[key] === undefined || typeof node[key] !== "object")
            node[key] = {};
        node = node[key];
    }
    node[parts[parts.length - 1]] = value;
}
