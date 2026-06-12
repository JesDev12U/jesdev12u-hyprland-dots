#!/bin/sh

# File to cache zoom factor (stored in RAM/tmpfs)
zoom_file="/tmp/current_zoom"

# Read current cached value (default to 100 which represents 1.00)
if [ -f "$zoom_file" ]; then
    read -r current < "$zoom_file"
    # Ensure it's a valid integer
    case "$current" in
        ''|*[!0-9]*) current=100 ;;
    esac
else
    current=100
fi

# Step size (5 represents 0.05 zoom factor step)
step=5
max_zoom=500  # 5.0x zoom limit
min_zoom=100  # 1.0x zoom limit (no zoom)

case "$1" in
    in)
        new=$((current + step))
        if [ "$new" -gt "$max_zoom" ]; then
            new=$max_zoom
        fi
        ;;
    out)
        new=$((current - step))
        if [ "$new" -lt "$min_zoom" ]; then
            new=$min_zoom
        fi
        ;;
    reset)
        new=100
        ;;
    *)
        echo "Usage: $0 {in|out|reset}"
        exit 1
        ;;
esac

# Save to cache file
echo "$new" > "$zoom_file"

# Format float string
float_val=$(printf "%d.%02d" $((new / 100)) $((new % 100)))

# Apply the zoom factor and trigger launcher interrupt in a single batch call
hyprctl --batch "keyword cursor:zoom_factor $float_val ; dispatch global caelestia:launcherInterrupt"
