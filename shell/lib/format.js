.pragma library

function clampPercent(value) {
    if (!isFinite(value))
        return 0;
    return Math.max(0, Math.min(100, Math.round(value)));
}

function signalPercent(strength) {
    if (!isFinite(strength))
        return 0;
    return clampPercent(strength <= 1 ? strength * 100 : strength);
}

function securityLabel(name) {
    const value = String(name || "");
    if (value === "Open")
        return "Open";
    if (value === "Owe")
        return "OWE";
    if (value === "Sae" || value.indexOf("Wpa3") === 0)
        return "WPA3";
    if (value.indexOf("Wpa2") === 0)
        return "WPA2";
    if (value.indexOf("Wpa") === 0)
        return "WPA";
    if (value.indexOf("Wep") >= 0)
        return "WEP";
    if (value === "Leap")
        return "LEAP";
    return "";
}

function failureLabel(reason) {
    if (reason === "NoSecrets")
        return "Password required";
    if (reason === "WifiAuthTimeout")
        return "Authentication timed out";
    if (reason === "WifiNetworkLost")
        return "Network lost";
    if (reason === "WifiClientDisconnected")
        return "Disconnected";
    if (reason === "WifiClientFailed")
        return "Connection failed";
    return "Connection failed";
}

function duration(seconds) {
    if (!isFinite(seconds) || seconds <= 0)
        return "";
    const minutes = Math.max(1, Math.round(seconds / 60));
    if (minutes < 60)
        return minutes + "m";
    const hours = Math.floor(minutes / 60);
    return hours + "h " + (minutes % 60) + "m";
}

function round1(value) {
    return Math.round(value * 10) / 10;
}

function watts(value) {
    if (!isFinite(value))
        return "";
    return round1(Math.abs(value)).toFixed(1) + " W";
}

function energy(value) {
    if (!isFinite(value))
        return "";
    return round1(value).toFixed(1) + " Wh";
}
