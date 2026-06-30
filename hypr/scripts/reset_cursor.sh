#!/bin/sh
# Workaround for SDDM/KDE ghost cursor stuck in the center of the screen
sleep 2.5 && hyprctl eval 'hl.dispatch(hl.dsp.cursor.move({ x = 9999, y = 9999 }))'
sleep 0.5 && hyprctl eval 'hl.dispatch(hl.dsp.cursor.move({ x = 1, y = 1 }))'
