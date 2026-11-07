.pragma library

function defaults() {
    return {
        name: "",
        comment: "",
        exec: "",
        icon: "",
        terminal: false,
        noDisplay: false,
        hidden: false,
        onlyShowIn: [],
        notShowIn: [],
        categories: []
    };
}

function unescapeValue(value) {
    return value.replace(/\\([sntr\\])/g, function(match, code) {
        if (code === "s")
            return " ";
        if (code === "n")
            return "\n";
        if (code === "t")
            return "\t";
        if (code === "r")
            return "\r";
        return "\\";
    });
}

function boolValue(value) {
    const normalized = value.trim().toLowerCase();
    return normalized === "true" || normalized === "1" || normalized === "yes";
}

function listValue(value) {
    return value.split(";").map(function(item) {
        return item.trim();
    }).filter(function(item) {
        return item.length > 0;
    });
}

function parse(text) {
    const entry = defaults();
    if (!text)
        return entry;

    const lines = String(text).split(/\r?\n/);
    let inDesktopEntry = false;
    let foundSection = false;

    for (let i = 0; i < lines.length; i++) {
        const raw = lines[i];
        const line = raw.trim();
        if (line.length === 0 || line.charAt(0) === "#")
            continue;

        if (line.charAt(0) === "[" && line.charAt(line.length - 1) === "]") {
            inDesktopEntry = line === "[Desktop Entry]";
            if (inDesktopEntry)
                foundSection = true;
            continue;
        }
        if (!inDesktopEntry)
            continue;

        const eq = line.indexOf("=");
        if (eq <= 0)
            continue;

        const key = line.slice(0, eq).trim();
        const value = unescapeValue(line.slice(eq + 1).trim());
        if (key === "Name")
            entry.name = value;
        else if (key === "Comment")
            entry.comment = value;
        else if (key === "Exec")
            entry.exec = value;
        else if (key === "Icon")
            entry.icon = value;
        else if (key === "Terminal")
            entry.terminal = boolValue(value);
        else if (key === "NoDisplay")
            entry.noDisplay = boolValue(value);
        else if (key === "Hidden")
            entry.hidden = boolValue(value);
        else if (key === "OnlyShowIn")
            entry.onlyShowIn = listValue(value);
        else if (key === "NotShowIn")
            entry.notShowIn = listValue(value);
        else if (key === "Categories")
            entry.categories = listValue(value);
    }

    if (!foundSection)
        entry.name = "";
    return entry;
}

function matchesVisibility(entry, currentDesktops) {
    const current = (Array.isArray(currentDesktops) ? currentDesktops : []).map(function(item) {
        return String(item).toLowerCase();
    });

    if (entry.onlyShowIn.length > 0) {
        let visible = false;
        for (let i = 0; i < entry.onlyShowIn.length; i++) {
            if (current.indexOf(entry.onlyShowIn[i].toLowerCase()) >= 0) {
                visible = true;
                break;
            }
        }
        if (!visible)
            return false;
    }

    for (let i = 0; i < entry.notShowIn.length; i++) {
        if (current.indexOf(entry.notShowIn[i].toLowerCase()) >= 0)
            return false;
    }
    return true;
}

function collectFiles(files, currentDesktops) {
    const seen = ({});
    const found = [];

    for (let i = 0; i < files.length; i++) {
        const file = files[i];
        if (!file || !file.path)
            continue;
        const filename = String(file.path).split("/").pop();
        if (!filename || seen[filename])
            continue;
        seen[filename] = true;

        const entry = parse(file.text);
        entry.path = file.path;
        entry.id = filename.replace(/\.desktop$/, "");
        if (!entry.name || !entry.exec || entry.hidden || entry.noDisplay)
            continue;
        if (!matchesVisibility(entry, currentDesktops))
            continue;
        found.push(entry);
    }

    found.sort(function(a, b) {
        return a.name.localeCompare(b.name);
    });
    return found;
}

function splitArgs(value) {
    const args = [];
    let token = "";
    let quote = "";
    let escaped = false;

    for (let i = 0; i < value.length; i++) {
        const ch = value.charAt(i);
        if (escaped) {
            token += ch;
            escaped = false;
        } else if (ch === "\\") {
            escaped = true;
        } else if (quote.length > 0) {
            if (ch === quote)
                quote = "";
            else
                token += ch;
        } else if (ch === "\"" || ch === "'") {
            quote = ch;
        } else if (/\s/.test(ch)) {
            if (token.length > 0) {
                args.push(token);
                token = "";
            }
        } else {
            token += ch;
        }
    }
    if (escaped)
        token += "\\";
    if (token.length > 0)
        args.push(token);
    return args;
}

function resolveExec(exec) {
    if (!exec)
        return [];
    const result = [];
    const args = splitArgs(String(exec));
    for (let i = 0; i < args.length; i++) {
        const stripped = args[i].replace(/%[fFuUiIckKdDnNvVm]/g, "");
        if (stripped.length > 0)
            result.push(stripped);
    }
    return result;
}
