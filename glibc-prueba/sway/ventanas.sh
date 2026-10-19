#!/usr/bin/bash
# Selector de ventanas (SUPER+TAB, como el de HyDE): elige con fuzzel y enfoca.
sel=$(swaymsg -t get_tree | jq -r '.. | select(.pid? and (.type == "con" or .type == "floating_con"))
        | "\(.id)  \(.app_id // .window_properties.class // "?")  —  \(.name)"' | fuzzel --dmenu --prompt "ventana > ")
[ -n "$sel" ] && swaymsg "[con_id=${sel%% *}] focus"
