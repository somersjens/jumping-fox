#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cache_dir="/tmp/jumping-fox-swift-cache"
master="$root/promo/master-video.swift"

cd "$root"
# START is the unfreeze in the raw (after simulator home / launch). Event
# timestamps are relative to that same instant, so a wrong START both shows
# the homescreen and shifts every SFX. AUDIO_DELAY pulls landings onto the
# squash. iPhone stays a 15s App Store cut; iPad is longer so the end icon
# hold matches iPhone (~3.59s after completion_launch).
xcrun swift -module-cache-path "$cache_dir" -framework AVFoundation "$master" \
  promo/captures/iphone-final-raw.mp4 \
  promo/exports/jumping-fox-app-store-teaser-886x1920.mp4 \
  886 1920 2.15 15 promo/captures/iphone-final-events.tsv -0.10

# Give VideoToolbox a moment to release the first decoder before starting the
# second full-resolution export. This avoids intermittent decoder timeouts when
# the two masters are rendered back-to-back on a busy machine.
sleep 5

xcrun swift -module-cache-path "$cache_dir" -framework AVFoundation "$master" \
  promo/captures/ipad-final-raw.mp4 \
  promo/exports/jumping-fox-app-store-teaser-1200x1600.mp4 \
  1200 1600 2.10 17.65 promo/captures/ipad-final-events.tsv -0.10
