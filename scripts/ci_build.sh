#!/bin/bash
# Husk: build everything from a clean checkout to the IPA, in order.
#
# Runs on macOS with Xcode. Usage: ./scripts/ci_build.sh [output.ipa]
set -euo pipefail

HUSK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HUSK_ROOT/build/Husk.ipa}"
cd "$HUSK_ROOT"

step() { printf '\n\033[1;34m##### %s\033[0m\n' "$*"; }

step "fetch sources"
./scripts/fetch_sources.sh

step "dependencies: libffi glib pixman libucontext libslirp"
./scripts/build_ios.sh libffi glib pixman libucontext libslirp

# build_gpu_ios.sh asks for cross-ios-darwin.meson, which no script generates.
# build_ios.sh writes cross-darwin.meson, the file it describes (host system
# darwin, subsystem ios), under a different name.
cp build/ios-arm64/cross-darwin.meson build/ios-arm64/cross-ios-darwin.meson

if [ ! -f build/ios-arm64/sysroot/lib/libANGLE-shared.dylib ]; then
    step "ANGLE (EGL/GLES over Metal)"
    ./scripts/build_angle_ios.sh
fi

if [ ! -f build/ios-arm64/sysroot/lib/libvirglrenderer.a ]; then
    step "libepoxy + virglrenderer"
    # build_ios.sh's cross environment, which the GPU script assumes is set.
    PKG_CONFIG_LIBDIR="$HUSK_ROOT/build/ios-arm64/sysroot/lib/pkgconfig:$HUSK_ROOT/build/ios-arm64/sysroot/share/pkgconfig" \
        ./scripts/build_gpu_ios.sh
fi

step "QEMU"
./scripts/build_ios.sh qemu

# QEMU is re-linked only when its staged dylib is absent.
#
# These two steps had no guard, and that was expensive: build_ios.sh rewrites the
# meson cross file with whatever clang the *current* Xcode provides, so changing
# the Xcode version makes meson see a different compiler and reconfigure --
# recompiling all of QEMU, ~35 minutes, to produce the same iOS arm64 dylib.
# integrate_husk.sh is idempotent and its result is already inside the dylib that
# is sitting in build/ios-arm64/lib, so both can be skipped when it is there.
if [ ! -f build/ios-arm64/lib/libqemu-aarch64-softmmu.dylib ]; then
    step "integrate Husk sources into QEMU, then rebuild it"
    ./scripts/integrate_husk.sh
    ./scripts/build_ios.sh qemurebuild
else
    echo "[skip] QEMU dylib already staged"
fi

step "guest kernel + firmware"
./scripts/fetch_phase0_guest.sh

if [ ! -d build/ios-arm64/lib/MoltenVK.xcframework ]; then
    step "MoltenVK (Vulkan over Metal, for Unreal Engine games)"
    ./scripts/build_moltenvk_ios.sh
fi

if [ ! -f build/ios-arm64/lib/libhusk_rppairing.a ]; then
    step "on-device pairing (Rust)"
    ./scripts/build_rppairing_ios.sh
else
    echo "[skip] rppairing already built"
fi

step "app + IPA"
mkdir -p "$(dirname "$OUT")"
./scripts/package_ipa.sh "$OUT"
./scripts/package_ipa.sh --trollstore "${OUT%.ipa}.tipa"
