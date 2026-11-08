#!/usr/bin/env python3
"""Removes cores that failed to build from project.yml (so one broken core can't block the app),
and writes App/Resources/cores-available.json so the app knows which systems it can run."""
import json, os, re, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cores = json.load(open(os.path.join(root, "cores", "cores.json")))["cores"]
available, missing = [], []
for c in cores:
    path = os.path.join(root, "Vendor", "Cores", c["framework"] + ".xcframework")
    (available if os.path.isdir(path) else missing).append(c)
project = open(os.path.join(root, "project.yml")).read()
for c in missing:
    project = re.sub(r"      - framework: Vendor/Cores/%s\.xcframework\n(        .*\n)*?        codeSign: true\n" % re.escape(c["framework"]), "", project)
open(os.path.join(root, "project.yml"), "w").write(project)
json.dump([c["framework"] for c in available], open(os.path.join(root, "App", "Resources", "cores-available.json"), "w"))
# Runtime data files (fonts, shaders) go in a folder reference so their directory layout is kept.
import shutil
assets_root = os.path.join(root, "App", "CoreAssets")
shutil.rmtree(assets_root, ignore_errors=True)
os.makedirs(assets_root)
open(os.path.join(assets_root, "README.txt"), "w").write("Core data files copied to the system folder on launch.\n")
for c in available:
    src = os.path.join(root, "Vendor", "Cores", c["framework"] + ".assets")
    if os.path.isdir(src):
        shutil.copytree(src, os.path.join(assets_root, c["framework"]))
print("cores available:", ", ".join(c["id"] for c in available) or "none")
if missing:
    print("::warning::cores that failed to build: " + ", ".join(c["id"] for c in missing))
