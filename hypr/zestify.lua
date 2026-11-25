-- Zestify user bindings. Installed to ~/.config/hypr/conf/zestify.lua
-- and required from binds.lua inside the zestify-binds marker block.

-- Let an authenticated replacement locker take over if Quickshell crashes.
-- The compositor keeps the session covered throughout recovery.
hl.config({ misc = { allow_session_lock_restore = true } })

-- The opt-in Dolphin theme supplies its own softer window corners.
local dolphin_profile = os.getenv("HOME") .. "/.config/zestify/theme/dolphin.lua"
local dolphin_file = io.open(dolphin_profile, "r")
if dolphin_file then
    dolphin_file:close()
    dofile(dolphin_profile)
end

-- Graphical sessions often omit ~/.local/bin from PATH. Quote the executable
-- for exec_cmd's shell, including paths with spaces or apostrophes.
local executable = os.getenv("ZESTI_BIN") or os.getenv("ZESTIFY_BIN")
    or (os.getenv("HOME") .. "/.local/bin/zesti")
local function command(arguments)
    return "'" .. executable:gsub("'", "'\\''") .. "' " .. arguments
end

local function bind(key, arguments)
    -- Replace earlier legacy bindings for these owned shortcuts.
    hl.unbind(key)
    hl.bind(key, hl.dsp.exec_cmd(command(arguments)))
end

bind("SUPER + Escape", "lock")
bind("SUPER + D", "shell open launcher")
bind("SUPER + W", "shell open wallpaper")
bind("SUPER + P", "capture screenshot")

return { command = command }
