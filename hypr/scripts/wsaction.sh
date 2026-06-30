#!/bin/sh

group=0
if [ "$1" = "-g" ]; then
    group=1
    shift
fi

if [ "$#" -ne 2 ]; then
    echo 'Wrong number of arguments. Usage: ./wsaction.sh [-g] <dispatcher> <workspace>'
    exit 1
fi

dispatcher="$1"
target_ws="$2"

active_ws=$(hyprctl activeworkspace -j | jq -r '.id')

if [ "$group" -eq 1 ]; then
    # Move to group
    res=$(( (target_ws - 1) * 10 + active_ws % 10 ))
else
    # Move to ws in group
    group_base=$(( (active_ws - 1) / 10 ))
    res=$(( group_base * 10 + target_ws ))
fi

if [ "$dispatcher" = "workspace" ]; then
    lua_disp="hl.dsp.focus({ workspace = '$res' })"
elif [ "$dispatcher" = "movetoworkspace" ]; then
    lua_disp="hl.dsp.window.move({ workspace = '$res' })"
else
    lua_disp="hl.dsp.focus({ workspace = '$res' })"
fi

hyprctl dispatch "$lua_disp"
