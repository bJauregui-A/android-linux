#!/usr/bin/bash
# SUPER+CTRL+↓: ir al primer escritorio libre (como "workspace empty" de Hyprland).
usados=$(swaymsg -t get_workspaces | jq '.[].num')
n=1
while grep -qx "$n" <<< "$usados"; do n=$((n + 1)); done
swaymsg workspace number $n
