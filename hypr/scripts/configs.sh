#!/bin/sh

_reload=0
config_dir="$1"

# Ensure config directory exists
if [ ! -d "$config_dir" ]; then
    mkdir -p "$config_dir"
fi

# Ensure hypr-vars exists
if [ ! -f "$config_dir/hypr-vars.conf" ]; then
    touch "$config_dir/hypr-vars.conf"
    _reload=1
fi

# Ensure hypr-user exists
if [ ! -f "$config_dir/hypr-user.conf" ]; then
    touch "$config_dir/hypr-user.conf"
    _reload=1
fi

# Reload as needed
if [ "$_reload" -eq 1 ]; then
    hyprctl reload
fi
