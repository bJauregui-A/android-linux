#!/usr/bin/bash
# SUPER+/: lista de atajos (como el de HyDE), sacada de la config de sway.
grep -E '^\s*bindsym' ~/.config/sway/config | sed -E 's/^\s*bindsym (--[a-z-]+ )*//; s/\$mod/SUPER/g; s/Mod1/ALT/g' |
  fuzzel --dmenu --prompt "atajos > " --width 60 > /dev/null
