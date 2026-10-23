#!/usr/bin/env python3
"""Generates the AppIcon.icon foreground layer: an open book with a bookmark ribbon.

The background is the gradient fill in AppIcon.icon/icon.json; this only draws the
transparent foreground, so Icon Composer can apply its glass, shadow and dark/tinted modes.
Run: python3 scripts/generate-app-icon.py
"""
import json, pathlib

root = pathlib.Path(__file__).resolve().parent.parent / "AppIcon.icon"
cx, top, bottom = 512, 300, 740          # spine x, page top, page bottom
half, curve = 300, 56                    # half-width of the spread, page dip at the spine

def page(side):
    s = side                              # -1 left, +1 right
    outer, spine = cx + s * half, cx
    return (f"M{spine},{top + curve} Q{cx + s * half * 0.5},{top - 30} {outer},{top} "
            f"L{outer},{bottom} Q{cx + s * half * 0.5},{bottom - 30 + curve // 2} {spine},{bottom + curve} Z")

def lines(side):
    s, out = side, []
    for i in range(4):
        y = 440 + i * 62
        x1, x2 = cx + s * 70, cx + s * (250 - (40 if i == 3 else 0))
        out.append(f'<line x1="{x1}" y1="{y + (curve * 0.5 if False else 0)}" x2="{x2}" y2="{y - 14}" '
                   f'stroke="#6C7BE0" stroke-width="22" stroke-linecap="round" opacity="0.55"/>')
    return "\n    ".join(out)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Page stack shadow edge -->
  <path d="M{cx - half - 24},{top + 24} L{cx - half - 24},{bottom + 36} Q{cx - half * 0.5},{bottom + 8 + curve // 2} {cx},{bottom + curve + 36} Q{cx + half * 0.5},{bottom + 8 + curve // 2} {cx + half + 24},{bottom + 36} L{cx + half + 24},{top + 24} Z" fill="#3B4BB8"/>
  <!-- Pages -->
  <path d="{page(-1)}" fill="#FFFFFF"/>
  <path d="{page(1)}" fill="#F1F3FF"/>
  <g>
    {lines(-1)}
    {lines(1)}
  </g>
  <!-- Spine crease -->
  <line x1="{cx}" y1="{top + curve}" x2="{cx}" y2="{bottom + curve}" stroke="#C9CFF5" stroke-width="6"/>
  <!-- Bookmark ribbon -->
  <path d="M{cx + 150},{top - 18} L{cx + 150},{top + 210} L{cx + 195},{top + 165} L{cx + 240},{top + 210} L{cx + 240},{top - 6} Z" fill="#FF5C7A"/>
</svg>
'''
(root / "Assets" / "Book.svg").write_text(svg)

icon = {
    "fill": {"linear-gradient": ["display-p3:0.36,0.40,0.95,1.0", "display-p3:0.16,0.12,0.50,1.0"]},
    "groups": [{
        "layers": [{"image-name": "Book.svg", "name": "Book", "position": {"scale": 1, "translation-in-points": [0, 0]}}],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": True, "value": 0.2},
    }],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}
(root / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
old = root / "Assets" / "Minimal_PureCopy.svg"
old.unlink(missing_ok=True)
print("wrote", root / "Assets" / "Book.svg")
