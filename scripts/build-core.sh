#!/bin/bash
# Builds one libretro core for iPhone + Simulator as a dynamic framework inside an XCFramework:
#   Vendor/Cores/<Framework>.xcframework
# The app embeds these frameworks and loads them with dlopen (the same approach RetroArch uses on the App Store).
# usage: scripts/build-core.sh <core id>      (ids are listed in cores/cores.json)
set -euo pipefail
ID="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIN_IOS="17.0"
read -r FW REPO SHA DIR MK ARGS BUILD ASSETS CCEXTRA < <(python3 - "$ROOT/cores/cores.json" "$ID" <<'PY'
import json, sys
c = next(c for c in json.load(open(sys.argv[1]))["cores"] if c["id"] == sys.argv[2])
print(c["framework"], c["repo"], c["sha"], c.get("dir", "."), c.get("makefile", "Makefile"),
      c.get("args", "").replace(" ", "|") or "-", c.get("build", "make"), c.get("assets", "-"),
      c.get("cflags", "").replace(" ", "|") or "-")
PY
)
[ "$ARGS" = "-" ] && ARGS=""
ARGS="${ARGS//|/ }"
[ "$CCEXTRA" = "-" ] && CCEXTRA=""
CCEXTRA="${CCEXTRA//|/ }"
OUT="$ROOT/Vendor/Cores/$FW.xcframework"
STAMP="$ROOT/Vendor/Cores/.$ID"
if [ -d "$OUT" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$SHA" ]; then echo "$ID already built"; exit 0; fi

WORK="$ROOT/build/cores/$ID"
mkdir -p "$WORK"
if [ ! -d "$WORK/src/.git" ]; then
  git init -q "$WORK/src"
  git -C "$WORK/src" remote add origin "https://github.com/$REPO.git"
fi
git -C "$WORK/src" fetch -q --depth 1 origin "$SHA"
git -C "$WORK/src" checkout -q -f FETCH_HEAD
git -C "$WORK/src" submodule update -q --init --recursive --depth 1 || true
JOBS="$(sysctl -n hw.ncpu)"

make_framework() { # dylib slice-name
  local dylib="$1" slice="$2" fwdir="$WORK/fw-$2/$FW.framework"
  rm -rf "$fwdir"; mkdir -p "$fwdir"
  cp "$dylib" "$fwdir/$FW"
  install_name_tool -id "@rpath/$FW.framework/$FW" "$fwdir/$FW"
  local platform="iPhoneOS"; [ "$slice" = "sim" ] && platform="iPhoneSimulator"
  cat > "$fwdir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$FW</string>
  <key>CFBundleIdentifier</key><string>com.fuxkingjosh.emu4ios.core.$ID</string>
  <key>CFBundleName</key><string>$FW</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict></plist>
PLIST
}

build_make() { # slice sdk target
  local slice="$1" sdk="$2" target="$3"
  local sdkpath; sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local cc="$(xcrun -f clang) -target $target -isysroot $sdkpath $CCEXTRA"
  local cxx="$(xcrun -f clang++) -target $target -isysroot $sdkpath $CCEXTRA"
  local ccas="$(xcrun -f clang) -target $target -isysroot $sdkpath" # no extra flags for assembly
  make -C "$WORK/src/$DIR" -f "$MK" clean >/dev/null 2>&1 || true
  find "$WORK/src" -name "*.dylib" -delete
  touch "$WORK/build-$slice.log.start"; sleep 1
  # shellcheck disable=SC2086
  make -C "$WORK/src/$DIR" -f "$MK" platform=ios-arm64 IOSSDK="$sdkpath" MINVERSION= \
    CC="$cc" CXX="$cxx" CC_AS="$ccas" AS="$ccas" LD="$cxx" $ARGS -j "$JOBS" > "$WORK/build-$slice.log" 2>&1 \
    || { echo "---- errors ----"; grep -E -A4 "error:|Undefined symbols" "$WORK/build-$slice.log" | head -80; echo "---- end of log ----"; tail -25 "$WORK/build-$slice.log"; exit 1; }
  local lib; lib="$(find "$WORK/src" -maxdepth 5 -name "*.dylib" -newer "$WORK/build-$slice.log.start" 2>/dev/null | head -1)"
  [ -n "$lib" ] || { echo "no dylib produced for $ID ($slice)"; tail -30 "$WORK/build-$slice.log"; exit 1; }
  make_framework "$lib" "$slice"
  rm -f "$lib"
}

build_cmake() { # slice sysroot
  local slice="$1" sysroot="$2" bdir="$WORK/cmake-$1"
  rm -rf "$bdir"
  # shellcheck disable=SC2086
  cmake -S "$WORK/src" -B "$bdir" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sysroot" -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" -DBUILD_SHARED_LIBS=OFF $ARGS > "$WORK/cmake-$slice.log" 2>&1 \
    || { tail -60 "$WORK/cmake-$slice.log"; exit 1; }
  cmake --build "$bdir" -j "$JOBS" > "$WORK/build-$slice.log" 2>&1 || { tail -80 "$WORK/build-$slice.log"; exit 1; }
  local lib; lib="$(find "$bdir" -name "*libretro*.dylib" | head -1)"
  [ -n "$lib" ] || { echo "no dylib produced for $ID ($slice)"; exit 1; }
  make_framework "$lib" "$slice"
}

if [ "$BUILD" = "cmake" ]; then
  build_cmake ios iphoneos
  build_cmake sim iphonesimulator
else
  build_make ios iphoneos "arm64-apple-ios$MIN_IOS"
  build_make sim iphonesimulator "arm64-apple-ios$MIN_IOS-simulator"
fi

mkdir -p "$ROOT/Vendor/Cores"
rm -rf "$OUT"
xcodebuild -create-xcframework \
  -framework "$WORK/fw-ios/$FW.framework" \
  -framework "$WORK/fw-sim/$FW.framework" \
  -output "$OUT" >/dev/null
# Data files some cores need at runtime (PPSSPP fonts and shaders), copied to the app's system folder on first launch.
if [ "$ASSETS" != "-" ]; then
  rm -rf "$ROOT/Vendor/Cores/$FW.assets"
  cp -R "$WORK/src/$ASSETS" "$ROOT/Vendor/Cores/$FW.assets"
fi
echo "$SHA" > "$STAMP"
echo "Built $OUT"
