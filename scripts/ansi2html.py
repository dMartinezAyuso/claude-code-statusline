#!/usr/bin/env python3
"""Turns the ANSI output of statusline.sh (stdin) into a small HTML page that looks like a terminal.
OSC 8 links are dropped, SGR codes 0, 1, 2 and 30-37 are kept. Used only to render the README images."""
import html
import re
import sys

COLORS = {30: "#6e7681", 31: "#ff7b72", 32: "#3fb950", 33: "#e3b341", 34: "#79c0ff", 35: "#d2a8ff", 36: "#56d4dd", 37: "#e6edf3"}
text = re.sub(r"\x1b\]8;;[^\x07]*\x07", "", sys.stdin.read())
out, bold, dim, color = [], False, False, None
open_span = False
for part in re.split(r"(\x1b\[[0-9;]*m)", text):
    m = re.fullmatch(r"\x1b\[([0-9;]*)m", part)
    if not m:
        if part:
            style = []
            if color:
                style.append(f"color:{color}")
            if bold:
                style.append("font-weight:700")
            if dim:
                style.append("opacity:.6")
            esc = html.escape(part)
            out.append(f'<span style="{";".join(style)}">{esc}</span>' if style else esc)
        continue
    for code in (int(c or 0) for c in m.group(1).split(";")):
        if code == 0:
            bold = dim = False
            color = None
        elif code == 1:
            bold = True
        elif code == 2:
            dim = True
        elif code in COLORS:
            color = COLORS[code]
print(f"""<!doctype html><meta charset=utf-8><body style="margin:0;background:#0d1117">
<pre style="margin:0;padding:18px 22px;display:inline-block;color:#e6edf3;background:#0d1117;
font:15px/1.5 Menlo,Monaco,'SF Mono',monospace;white-space:pre">{''.join(out)}</pre>""")
