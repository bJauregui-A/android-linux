#!/usr/bin/env bash
# Reinstala para el usuario 0 todo lo listado en eliminados.txt
cd "$(dirname "$0")"
while read -r p; do [ -n "$p" ] && echo "$p: $(adb shell cmd package install-existing "$p")"; done < eliminados.txt
