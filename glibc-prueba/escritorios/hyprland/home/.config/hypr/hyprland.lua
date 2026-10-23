-- Configuración de Hyprland en el teléfono
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 3,
})

hl.on("hyprland.start", function ()
    hl.exec_cmd("waybar -c /usr/local/share/linux-android/escritorios/comun/waybar.jsonc")
end)

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
    debug = {
        disable_scale_checks = true,
    },
    general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border   = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding       = 10,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },
    animations = {
        enabled = true,
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = false,
    },
    input = {
        kb_layout    = "latam",
        follow_mouse = 1,
        sensitivity  = 0,
    },
})

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

local mainMod = "SUPER"
local terminal_cmd = "sh -c 'command -v kitty >/dev/null 2>&1 && exec kitty || command -v foot >/dev/null 2>&1 && exec foot || command -v konsole >/dev/null 2>&1 && exec konsole || command -v alacritty >/dev/null 2>&1 && exec alacritty || exec xterm'"
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal_cmd))
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd(terminal_cmd))
hl.bind(mainMod .. " + Q",      hl.dsp.window.close())
hl.bind(mainMod .. " + A",      hl.dsp.exec_cmd("fuzzel"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("dolphin"))
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + left",   hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right",  hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",     hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",   hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
