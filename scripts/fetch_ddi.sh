#!/usr/bin/env bash
# The Developer Disk Image the built-in StikJIT helper mounts before it
# attaches. StikJIT otherwise downloads it from GitHub on the spot, over the
# phone's own network, and a route that cannot reach github.com fails the
# mount with "Failed to download Developer Disk Image". Bundling the files
# into the helper means the first mount needs no network at all: the helper
# seeds its Library/StikJIT/DDI cache from its own resources.
#
# 16 MB in total, so this is cheap to carry. The Cryptex format is
# version-independent -- one copy serves every supported iOS release -- unlike
# the older per-version PersonalizedImages.
#
# Idempotent: a file already present at the expected size is left alone, so
# later runs cost nothing.
set -euo pipefail

HUSK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HUSK_ROOT/src/app/HuskJITHelper/Resources/DDI"
BASE="https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Cryptex"

# name and exact size, so a truncated download is caught here rather than
# shipped in an app that fails to mount with no explanation.
FILES='
BuildManifest.plist 804946
Image.dmg 15895040
Image.dmg.cryptex_info 430
Image.dmg.root_hash 229
Image.dmg.trustcache 1895
'

size_of() {
    wc -c < "$1" | tr -d '[:space:]'
}

mkdir -p "$DEST"

while read -r name want; do
    [ -n "${name:-}" ] || continue
    out="$DEST/$name"

    if [ -f "$out" ] && [ "$(size_of "$out")" = "$want" ]; then
        echo "==> DDI $name present ($want bytes)"
        continue
    fi

    echo "==> fetching DDI $name ($want bytes)"
    fetched=0
    for attempt in 1 2 3 4 5; do
        if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
                -o "$out.part" "$BASE/$name"; then
            got="$(size_of "$out.part")"
            if [ "$got" = "$want" ]; then
                mv "$out.part" "$out"
                fetched=1
                break
            fi
            echo "    short read: $got of $want bytes" >&2
        fi
        rm -f "$out.part"
        if [ "$attempt" = 5 ]; then
            echo "error: could not fetch $name after 5 attempts" >&2
            exit 1
        fi
        sleep 3
    done
    [ "$fetched" = 1 ] || exit 1
done <<< "$FILES"

echo "--- $DEST ---"
ls -l "$DEST"
