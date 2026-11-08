import json, os, sys
from PIL import Image, ImageDraw, ImageFilter
root = sys.argv[1]
S = 1024
def grad(c1, c2):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return img
def icon(bg1, bg2, body, screen, dpad, a, b, glow=None):
    img = grad(bg1, bg2)
    d = ImageDraw.Draw(img)
    if glow:
        g = Image.new("RGB", (S, S), (0, 0, 0)); gd = ImageDraw.Draw(g)
        gd.rounded_rectangle([250, 140, 774, 884], 90, fill=glow)
        g = g.filter(ImageFilter.GaussianBlur(60))
        img = Image.blend(img, Image.composite(g, img, g.convert("L")), 0.6); d = ImageDraw.Draw(img)
    # handheld body
    d.rounded_rectangle([262, 150, 762, 874], 80, fill=body)
    # screen bezel + screen
    d.rounded_rectangle([312, 205, 712, 520], 36, fill=tuple(max(0, c - 40) for c in body))
    d.rounded_rectangle([352, 240, 672, 485], 18, fill=screen)
    # "4" pixel glyph on screen
    px = 22; ox, oy = 470, 290
    glyph = ["1001", "1001", "1111", "0001", "0001", "0001"]
    for r, row in enumerate(glyph):
        for c, ch in enumerate(row):
            if ch == "1":
                d.rectangle([ox + c*px, oy + r*px, ox + c*px + px - 3, oy + r*px + px - 3], fill=tuple(max(0, v - 120) for v in screen))
    # d-pad
    cx, cy, arm, w = 395, 680, 85, 52
    d.rounded_rectangle([cx - w//2, cy - arm, cx + w//2, cy + arm], 12, fill=dpad)
    d.rounded_rectangle([cx - arm, cy - w//2, cx + arm, cy + w//2], 12, fill=dpad)
    # A/B
    d.ellipse([590, 590, 680, 680], fill=a)
    d.ellipse([530, 680, 620, 770], fill=b)
    return img
variants = {
    "AppIcon": ((124, 92, 255), (40, 20, 90), (236, 236, 244), (155, 188, 15), (40, 40, 52), (230, 40, 110), (230, 40, 110), None),
    "AppIcon-Neon": ((20, 4, 40), (7, 2, 15), (30, 14, 50), (0, 229, 255), (255, 43, 214), (255, 43, 214), (0, 229, 255), (255, 43, 214)),
    "AppIcon-Retro": ((196, 192, 180), (150, 146, 136), (216, 212, 200), (139, 172, 15), (42, 42, 51), (139, 30, 90), (139, 30, 90), None),
    "AppIcon-Candy": ((255, 209, 232), (201, 241, 255), (255, 255, 255), (255, 111, 174), (255, 111, 174), (255, 111, 174), (111, 200, 255), None),
    "AppIcon-Midnight": ((14, 14, 20), (0, 0, 0), (27, 27, 38), (124, 92, 255), (60, 60, 80), (124, 92, 255), (124, 92, 255), None),
    "AppIcon-Gold": ((255, 214, 102), (176, 112, 20), (40, 34, 26), (255, 200, 60), (90, 70, 40), (255, 200, 60), (255, 200, 60), (255, 190, 40)),
    "AppIcon-Ocean": ((60, 190, 255), (10, 50, 130), (230, 246, 255), (40, 170, 230), (20, 60, 110), (255, 140, 80), (255, 140, 80), None),
    "AppIcon-Lava": ((255, 90, 30), (80, 0, 10), (30, 18, 18), (255, 120, 40), (70, 30, 30), (255, 200, 40), (255, 80, 20), (255, 60, 0)),
    "AppIcon-Mint": ((190, 255, 220), (60, 190, 150), (255, 255, 255), (120, 220, 180), (40, 90, 80), (255, 120, 150), (255, 120, 150), None),
}
assets = os.path.join(root, "App/Resources/Assets.xcassets")
os.makedirs(assets, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(assets, "Contents.json"), "w"), indent=2)
previews = {k: "IconPreview-" + (k.split("-")[1] if "-" in k else "Default") for k in list(variants) + ["AppIcon-BigFour"]}
for name, v in variants.items():
    img = icon(*v)
    folder = os.path.join(assets, f"{name}.appiconset"); os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, "icon-1024.png"))
    json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(folder, "Contents.json"), "w"), indent=2)
    pf = os.path.join(assets, f"{previews[name]}.imageset"); os.makedirs(pf, exist_ok=True)
    img.resize((180, 180), Image.LANCZOS).save(os.path.join(pf, "preview.png"))
    json.dump({"images": [{"filename": "preview.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}},
              open(os.path.join(pf, "Contents.json"), "w"), indent=2)
def big_four():
    img = grad((124, 92, 255), (40, 20, 90)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([192, 192, 832, 832], 90, fill=(155, 188, 15))
    glyph = ["1001", "1001", "1111", "0001", "0001", "0001"]
    for r, row in enumerate(glyph):
        for c, ch in enumerate(row):
            if ch == "1": d.rectangle([352 + c*80, 272 + r*80, 352 + c*80 + 77, 272 + r*80 + 77], fill=(27, 58, 10))
    return img
variants_extra = {"AppIcon-BigFour": big_four()}
for name, img in variants_extra.items():
    folder = os.path.join(assets, f"{name}.appiconset"); os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, "icon-1024.png"))
    json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(folder, "Contents.json"), "w"), indent=2)
    pf = os.path.join(assets, f"{previews[name]}.imageset"); os.makedirs(pf, exist_ok=True)
    img.resize((180, 180), Image.LANCZOS).save(os.path.join(pf, "preview.png"))
    json.dump({"images": [{"filename": "preview.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}},
              open(os.path.join(pf, "Contents.json"), "w"), indent=2)
def color(name, rgb):
    f = os.path.join(assets, f"{name}.colorset"); os.makedirs(f, exist_ok=True)
    json.dump({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
        "red": f"{rgb[0]/255:.3f}", "green": f"{rgb[1]/255:.3f}", "blue": f"{rgb[2]/255:.3f}", "alpha": "1.000"}}}],
        "info": {"author": "xcode", "version": 1}}, open(os.path.join(f, "Contents.json"), "w"), indent=2)
color("LaunchBackground", (14, 14, 20))
color("AccentColor", (124, 92, 255))
# Montage for review
names = list(variants) + list(variants_extra)
m = Image.new("RGB", (len(names) * 260 + 20, 280), (30, 30, 30))
for i, name in enumerate(names):
    m.paste(Image.open(os.path.join(assets, f"{name}.appiconset/icon-1024.png")).resize((240, 240)), (20 + i * 260, 20))
m.save("/home/claude/tools/icons-preview.png")
print("ok")
