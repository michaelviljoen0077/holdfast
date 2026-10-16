#!/usr/bin/env bash
# Render a screenshot of the scene: ./shoot.sh <name> [extra user args...]
# e.g. ./shoot.sh wide --cam=wide --seed=7 --frames=150
GODOT="/c/Users/USER-PC/Desktop/Godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")"
mkdir -p shots
name="$1"; shift
"$GODOT" --path . --resolution 1920x1080 -- --capture="shots/$name.png" "$@" 2>&1 | grep -vE "^\s*$|Godot Engine v|Vulkan|NVIDIA|^$" | head -60
