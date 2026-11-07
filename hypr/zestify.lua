-- Zestify user bindings. Installed to ~/.config/hypr/conf/zestify.lua
-- and included from binds.lua inside the zestify-binds marker block.

hl.bind("SUPER + Escape", hl.dsp.exec_cmd("zestify lock"))
hl.bind("SUPER + D", hl.dsp.exec_cmd("zestify ipc launcher"))
hl.bind("SUPER + W", hl.dsp.exec_cmd("zestify ipc wallpaper"))
