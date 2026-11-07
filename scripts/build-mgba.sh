#!/bin/bash
# Builds mGBA (Game Boy / Game Boy Color / Game Boy Advance) as a static
# XCFramework for iPhone + Simulator. Runs on the cloud Mac in GitHub Actions.
set -euo pipefail

MGBA_COMMIT="${MGBA_COMMIT:-662dada8b79070bde93829a44d583c517fc5ec2d}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/mgba"
OUT="$ROOT/Vendor/mGBA.xcframework"
MIN_IOS="17.0"

if [ -d "$OUT" ] && [ -f "$ROOT/Vendor/.mgba-commit" ] && [ "$(cat "$ROOT/Vendor/.mgba-commit")" = "$MGBA_COMMIT" ]; then
  echo "mGBA $MGBA_COMMIT already built"
  exit 0
fi

mkdir -p "$WORK"
if [ ! -d "$WORK/src/.git" ]; then
  git init -q "$WORK/src"
  git -C "$WORK/src" remote add origin https://github.com/mgba-emu/mgba.git
fi
git -C "$WORK/src" fetch -q --depth 1 origin "$MGBA_COMMIT"
git -C "$WORK/src" checkout -q FETCH_HEAD

build_slice() {
  local name="$1" sysroot="$2" archs="$3"
  local dir="$WORK/build-$name"
  cmake -S "$WORK/src" -B "$dir" -G "Unix Makefiles" \
    -DLIBMGBA_ONLY=ON \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "$dir" --target mgba -j "$(sysctl -n hw.ncpu)"
  local lib="$dir/libmgba.a"
  [ -f "$lib" ] || { echo "libmgba.a not found for $name"; exit 1; }
  mkdir -p "$WORK/lib-$name"
  cp "$lib" "$WORK/lib-$name/libmgba.a"
}

build_slice ios iphoneos arm64
build_slice sim iphonesimulator "arm64;x86_64"

# Headers: public mGBA headers + generated flags + our exact compile defines.
HEADERS="$WORK/headers"
rm -rf "$HEADERS"
mkdir -p "$HEADERS"
cp -R "$WORK/src/include/." "$HEADERS/"
cp -R "$WORK/build-ios/include/." "$HEADERS/"
"$ROOT/scripts/gen-mgba-defines.sh" "$WORK/build-ios" "$HEADERS/mgba-defines.h"
echo "--- mgba-defines.h ---"; cat "$HEADERS/mgba-defines.h"

rm -rf "$OUT"
mkdir -p "$ROOT/Vendor"
xcodebuild -create-xcframework \
  -library "$WORK/lib-ios/libmgba.a" -headers "$HEADERS" \
  -library "$WORK/lib-sim/libmgba.a" -headers "$HEADERS" \
  -output "$OUT"
rm -rf "$ROOT/Vendor/mgba-include"
cp -R "$HEADERS" "$ROOT/Vendor/mgba-include"
echo "$MGBA_COMMIT" > "$ROOT/Vendor/.mgba-commit"
echo "Built $OUT"
