#!/bin/bash
# Builds the PCSX-ReARMed PlayStation core (GPL-2.0-or-later) as a static XCFramework for
# iPhone + Simulator. Interpreter only — iOS apps can't use a JIT.
set -euo pipefail

PCSX_COMMIT="${PCSX_COMMIT:-7b0e8f8fadfbce3d170d195b9d9eecaabfa08c8e}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/pcsx"
OUT="$ROOT/Vendor/PCSXReARMed.xcframework"
MIN_IOS="17.0"

if [ -d "$OUT" ] && [ -f "$ROOT/Vendor/.pcsx-commit" ] && [ "$(cat "$ROOT/Vendor/.pcsx-commit")" = "$PCSX_COMMIT" ]; then
  echo "PCSX-ReARMed $PCSX_COMMIT already built"
  exit 0
fi

mkdir -p "$WORK"
if [ ! -d "$WORK/src/.git" ]; then
  git init -q "$WORK/src"
  git -C "$WORK/src" remote add origin https://github.com/libretro/pcsx_rearmed.git
fi
git -C "$WORK/src" fetch -q --depth 1 origin "$PCSX_COMMIT"
git -C "$WORK/src" checkout -q FETCH_HEAD
git -C "$WORK/src" submodule update -q --init --recursive --depth 1

build_slice() {
  local name="$1" sdk="$2" minflag="$3"
  local sdkpath
  sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
  make -C "$WORK/src" -f Makefile.libretro clean >/dev/null 2>&1 || true
  make -C "$WORK/src" -f Makefile.libretro \
    platform=ios-arm64 STATIC_LINKING=1 HAVE_PHYSICAL_CDROM=0 DYNAREC=0 \
    IOSSDK="$sdkpath" MINVERSION="$minflag" \
    TARGET="libpcsx_$name.a" -j "$(sysctl -n hw.ncpu)" >"$WORK/build-$name.log" 2>&1 \
    || { tail -40 "$WORK/build-$name.log"; exit 1; }
  mkdir -p "$WORK/lib-$name"
  mv "$WORK/src/libpcsx_$name.a" "$WORK/lib-$name/libpcsx.a"
}

build_slice ios iphoneos "-miphoneos-version-min=$MIN_IOS"
build_slice sim iphonesimulator "-mios-simulator-version-min=$MIN_IOS"

HEADERS="$WORK/headers"
rm -rf "$HEADERS" && mkdir -p "$HEADERS"
echo "// PCSX-ReARMed exposes the standard libretro API (see App/Bridge/libretro.h)." > "$HEADERS/pcsx.h"

rm -rf "$OUT"
mkdir -p "$ROOT/Vendor"
xcodebuild -create-xcframework \
  -library "$WORK/lib-ios/libpcsx.a" -headers "$HEADERS" \
  -library "$WORK/lib-sim/libpcsx.a" -headers "$HEADERS" \
  -output "$OUT"
echo "$PCSX_COMMIT" > "$ROOT/Vendor/.pcsx-commit"
echo "Built $OUT"
