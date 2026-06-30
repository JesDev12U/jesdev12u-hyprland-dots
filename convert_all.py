import os
import re
from hyprconf2lua.parser import parse_config
from hyprconf2lua.codegen import Codegen

# Paths
WORKSPACE = "/home/jesdev12u/Projects/jesdev12u-hyprland-dots"
HYPR_DIR = os.path.join(WORKSPACE, "hypr")
HYPRLAND_DIR = os.path.join(HYPR_DIR, "hyprland")
CAELESTIA_DIR = os.path.join(WORKSPACE, "caelestia")

# 1. Load kb_vars from variables.conf
var_conf_path = os.path.join(HYPR_DIR, "variables.conf")
with open(var_conf_path, "r") as f:
    var_content = f.read()

kb_vars = {}
for line in var_content.splitlines():
    line = line.strip()
    if line.startswith("#") or not line:
        continue
    match = re.match(r"\$(\w+)\s*=\s*(.+)", line)
    if match:
        name, val = match.groups()
        val = val.split("#")[0].strip()
        if name.startswith("kb"):
            kb_vars[name] = val

def post_process_lua(lua_code, is_variables=False):
    # Use lambda to cleanly replace local_var_XYZ with concatenation
    lua_code = re.sub(
        r"local_var_(\w+)",
        lambda m: f'" .. {m.group(1)} .. "',
        lua_code
    )
    # Clean up empty strings and concatenations
    lua_code = re.sub(r'""\s*\.\.\s*', "", lua_code)
    lua_code = re.sub(r'\s*\.\.\s*""', "", lua_code)
    
    # For variables.lua, extract all local definitions and append return table
    if is_variables:
        local_vars = re.findall(r"^local\s+(\w+)\s*=", lua_code, re.MULTILINE)
        if local_vars:
            return_block = "\nreturn {\n"
            for v in local_vars:
                return_block += f"    {v} = {v},\n"
            return_block += "}\n"
            lua_code += return_block
            
    return lua_code

def convert_file(in_path, out_path, is_variables=False):
    print(f"Converting: {in_path} -> {out_path}")
    with open(in_path, "r") as f:
        content = f.read()
        
    # Replace kb variables in content (only if not variables.conf itself)
    expanded_content = content
    if not is_variables:
        for name, val in kb_vars.items():
            expanded_content = expanded_content.replace(f"${name}", val)
        
    # Parse and generate Lua
    config = parse_config(expanded_content)
    codegen = Codegen()
    lua_output = codegen.generate(config)
    
    # Post-process
    final_lua = post_process_lua(lua_output, is_variables)
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        f.write(final_lua)

def main():
    # Convert variables.conf
    convert_file(
        os.path.join(HYPR_DIR, "variables.conf"),
        os.path.join(HYPR_DIR, "variables.lua"),
        is_variables=True
    )
    
    # Convert all sub-configs in hyprland/
    for filename in os.listdir(HYPRLAND_DIR):
        if filename.endswith(".conf"):
            in_path = os.path.join(HYPRLAND_DIR, filename)
            out_path = os.path.join(HYPRLAND_DIR, filename.replace(".conf", ".lua"))
            convert_file(in_path, out_path)
            
    # Convert caelestia files
    for filename in ["hypr-vars.conf", "hypr-user.conf"]:
        in_path = os.path.join(CAELESTIA_DIR, filename)
        if os.path.exists(in_path):
            out_path = os.path.join(CAELESTIA_DIR, filename.replace(".conf", ".lua"))
            convert_file(in_path, out_path, is_variables=(filename == "hypr-vars.conf"))

if __name__ == "__main__":
    main()
