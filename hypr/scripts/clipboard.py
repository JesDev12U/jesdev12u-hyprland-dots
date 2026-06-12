#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import re
import sys
import subprocess
from pathlib import Path

def main():
    # 1. Parse arguments
    delete_mode = False
    if len(sys.argv) > 1 and sys.argv[1] in ("-d", "--delete"):
        delete_mode = True

    # 2. Get cliphist list
    try:
        clip_list_bytes = subprocess.check_output(["cliphist", "list"])
        clip_list = clip_list_bytes.decode("utf-8", errors="replace")
    except subprocess.CalledProcessError:
        sys.exit(0)

    if not clip_list.strip():
        subprocess.run(["fuzzel", "-d", "--prompt-only", "Clipboard is empty"])
        sys.exit(0)

    # 3. Create thumbnail directory in cache
    cache_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    thumb_dir = cache_dir / "cliphist" / "thumbnails"
    thumb_dir.mkdir(parents=True, exist_ok=True)

    # 4. Process lines to inject image previews for fuzzel
    fuzzel_input = []
    # Match cliphist lines like:
    # "6509\t[[ binary data 61 KiB png 494x551 ]]"
    # ID is group 1, extension is group 2
    pattern = re.compile(r"^([0-9]+)\s+(?:\[\[\s*)?binary.*(jpg|jpeg|png|bmp|gif)", re.IGNORECASE)

    for line in clip_list.splitlines():
        if not line:
            continue
        match = pattern.match(line)
        if match:
            item_id = match.group(1)
            ext = match.group(2).lower()
            thumb_path = thumb_dir / f"{item_id}.{ext}"

            # If not in cache, decode it and save to file
            if not thumb_path.exists():
                try:
                    # cliphist decode takes the exact same history line as input
                    decoded = subprocess.check_output(["cliphist", "decode"], input=line.encode("utf-8", errors="replace"), text=False)
                    thumb_path.write_bytes(decoded)
                except Exception:
                    pass

            if thumb_path.exists():
                # Append standard Rofi/Fuzzel dmenu icon format: entry\0icon\x1f/path/to/icon
                fuzzel_input.append(f"{line}\u0000icon\u001f{thumb_path}")
            else:
                fuzzel_input.append(line)
        else:
            fuzzel_input.append(line)

    # 5. Execute fuzzel in dmenu mode
    fuzzel_args = ["--line-height=48", "--lines=8", "--minimal-lines"]
    if delete_mode:
        fuzzel_args += ["--prompt=del > ", "--placeholder=Delete from clipboard"]
    else:
        fuzzel_args += ["--placeholder=Type to search clipboard"]

    try:
        proc = subprocess.run(
            ["fuzzel", "--dmenu"] + fuzzel_args,
            input="\n".join(fuzzel_input).encode("utf-8", errors="replace"),
            capture_output=True,
            check=True
        )
        chosen = proc.stdout.decode("utf-8", errors="replace").strip()
    except subprocess.CalledProcessError:
        # User dismissed fuzzel (e.g. pressed Esc)
        sys.exit(0)

    if not chosen:
        sys.exit(0)

    # Clean the selection by removing the icon suffix if present (in case fuzzel outputs it)
    chosen_clean = chosen.split("\x00")[0]

    # 6. Perform action
    if delete_mode:
        subprocess.run(["cliphist", "delete"], input=chosen_clean.encode("utf-8", errors="replace"), text=False)
    else:
        try:
            # Decode the selected item
            decoded = subprocess.check_output(["cliphist", "decode"], input=chosen_clean.encode("utf-8", errors="replace"), text=False)
            # Copy to wayland clipboard
            subprocess.run(["wl-copy"], input=decoded)
        except Exception:
            pass

    # 7. Clean up orphaned thumbnails
    try:
        active_ids = set()
        for line in clip_list.splitlines():
            if not line:
                continue
            parts = line.split(maxsplit=1)
            if parts and parts[0].isdigit():
                active_ids.add(parts[0])

        for file_path in thumb_dir.iterdir():
            if file_path.is_file() and file_path.stem.isdigit():
                if file_path.stem not in active_ids:
                    try:
                        file_path.unlink()
                    except Exception:
                        pass
    except Exception:
        pass

if __name__ == "__main__":
    main()
