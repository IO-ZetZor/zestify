.pragma library

function formatDuration(seconds) {
    const total = Math.max(0, Math.floor(Number(seconds) || 0));
    const minutes = Math.floor(total / 60);
    const secs = total % 60;
    return minutes + ":" + String(secs).padStart(2, "0");
}

function joinArtists(artists) {
    if (Array.isArray(artists))
        return artists.map(a => String(a).trim()).filter(a => a.length > 0).join(", ");
    return String(artists || "").trim();
}
