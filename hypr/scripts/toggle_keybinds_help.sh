#!/bin/bash

# Find the PID of the quickshell instance running our specific QML file
PID=$(pgrep -f "[q]uickshell -p /home/jesdev12u/.config/hypr/scripts/keybinds_help.qml")

if [ -n "$PID" ]; then
    kill "$PID"
else
    quickshell -p /home/jesdev12u/.config/hypr/scripts/keybinds_help.qml &
fi
