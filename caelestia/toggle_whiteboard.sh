#!/usr/bin/env bash

# Start Lorien with windowed mode and exact size of 600x450 physical pixels
lorien -w --resolution 600x450 &

# Wait for the Lorien window to appear (up to 3 seconds)
for i in {1..30}; do
  ADDR=$(hyprctl clients -j | jq -r '.[] | select(.class == "Lorien") | .address' | tail -n 1)
  if [ -n "$ADDR" ]; then
    # Ensure the window is floating
    FLOATING=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$ADDR\") | .floating")
    if [ "$FLOATING" = "false" ] || [ "$FLOATING" = "0" ] || [ -z "$FLOATING" ]; then
      hyprctl dispatch togglefloating "address:$ADDR"
    fi
    
    # Wait for the window state to settle
    sleep 0.3
    
    # Focus the window to make sure moveactive applies to it
    hyprctl dispatch focuswindow "address:$ADDR"
    
    # Get the current position in logical (compositor) coordinates
    X=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$ADDR\") | .at[0]")
    Y=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$ADDR\") | .at[1]")
    
    # Calculate offset to place the window at logical coordinate (68, 460) next to the bar
    DX=$((68 - X))
    DY=$((460 - Y))
    
    # Move the window relatively using moveactive (bypasses XWayland absolute scaling bugs)
    hyprctl dispatch moveactive $DX $DY
    break
  fi
  sleep 0.1
done
