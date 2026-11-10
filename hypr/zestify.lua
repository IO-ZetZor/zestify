-- Zestify user bindings. Installed to ~/.config/hypr/conf/zestify.lua
-- and required from binds.lua inside the zestify-binds marker block.

-- Graphical sessions often omit ~/.local/bin from PATH. Quote the executable
-- for exec_cmd's shell, including paths with spaces or apostrophes.
local executable = os.getenv("ZESTI_BIN") or os.getenv("ZESTIFY_BIN")
    or (os.getenv("HOME") .. "/.local/bin/zesti")
local function command(arguments)
    return "'" .. executable:gsub("'", "'\\''") .. "' " .. arguments
end

local function bind(key, arguments)
    -- Replace earlier Caelestia/legacy bindings for these owned shortcuts.
    hl.unbind(key)
    hl.bind(key, hl.dsp.exec_cmd(command(arguments)))
end

bind("SUPER + Escape", "lock")
bind("SUPER + D", "shell open launcher")
bind("SUPER + W", "shell open wallpaper")
bind("SUPER + P", "capture screenshot")

return { command = command }
