.pragma library

var MAX_HISTORY = 100;

function add(history, entry, max) {
    const limit = max > 0 ? max : MAX_HISTORY;
    const next = [entry].concat(history || []);
    return next.slice(0, limit);
}

function dismiss(history, id) {
    return (history || []).filter(entry => !entry || entry.id !== id);
}

function clear() {
    return [];
}

function shouldPopup(dnd) {
    return !dnd;
}
