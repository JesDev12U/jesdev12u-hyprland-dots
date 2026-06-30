#!/bin/bash

# Find the PID of the quickshell instance running our specific QML file
PID=$(pgrep -f "[q]uickshell -p $HOME/.config/hypr/scripts/keybinds_help.qml")

if [ -n "$PID" ]; then
    kill "$PID"
else
    quickshell -p "$HOME/.config/hypr/scripts/keybinds_help.qml" &
fi
