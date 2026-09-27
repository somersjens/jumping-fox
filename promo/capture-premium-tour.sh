#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
runtime_name="${SIMULATOR_RUNTIME:-iOS 26.5}"
bundle_id="Hakketjak.Jumping-Fox"
derived="$root/.build-premium-promo"
app="$derived/Build/Products/Debug-iphonesimulator/Jumping Fox.app"

device_id() {
  local name="$1"
  xcrun simctl list devices "$runtime_name" | awk -v needle="    $name (" '
    index($0, needle) == 1 {
      value = $(NF - 1)
      gsub(/[()]/, "", value)
      print value
      exit
    }
  '
}

iphone="${IPHONE_SIMULATOR:-$(device_id 'iPhone 17e')}"
ipad="${IPAD_SIMULATOR:-$(device_id 'iPad Pro 13-inch (M5)')}"

if [[ -z "$iphone" || -z "$ipad" ]]; then
  print -u2 "Could not find the required simulators in $runtime_name."
  print -u2 "Set IPHONE_SIMULATOR and IPAD_SIMULATOR to explicit UDIDs."
  exit 1
fi

cd "$root"
xcodebuild -project "Jumping Fox.xcodeproj" -scheme "Jumping Fox" \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG TRAILER_EXPORT' \
  CODE_SIGNING_ALLOWED=NO build

capture() {
  local label="$1"
  local udid="$2"
  local raw="$root/promo/captures/premium-$label-raw.mp4"
  local events="$root/promo/captures/premium-$label-events.tsv"
  local recorder_log="/tmp/jumping-fox-premium-$label-record.log"

  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true
  xcrun simctl install "$udid" "$app"
  xcrun simctl launch --terminate-running-process "$udid" "$bundle_id" \
    --export-premium-tour >/dev/null

  local container
  container="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
  local handshake="$container/Documents/AppStoreTeaser"
  local waited=0
  while [[ ! -f "$handshake/playback-ready" ]]; do
    sleep 0.1
    waited=$((waited + 1))
    if (( waited > 300 )); then
      print -u2 "$label did not become capture-ready"
      exit 1
    fi
  done

  : >"$recorder_log"
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$raw" \
    >"$recorder_log" 2>&1 &
  local recorder_pid=$!

  waited=0
  while ! grep -q "Recording started" "$recorder_log"; do
    sleep 0.05
    waited=$((waited + 1))
    if (( waited > 200 )); then
      kill -INT "$recorder_pid" 2>/dev/null || true
      print -u2 "$label screen recorder did not start"
      exit 1
    fi
  done
  sleep 2
  touch "$handshake/start"

  waited=0
  while [[ ! -f "$handshake/playback-complete" ]]; do
    sleep 0.1
    waited=$((waited + 1))
    if (( waited > 600 )); then
      kill -INT "$recorder_pid" 2>/dev/null || true
      print -u2 "$label did not complete its Premium loop"
      exit 1
    fi
  done
  sleep 0.5
  kill -INT "$recorder_pid" 2>/dev/null || true
  wait "$recorder_pid" || true
  cp "$handshake/events.tsv" "$events"
  xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  print "Captured $raw"
}

capture iphone "$iphone"
capture ipad "$ipad"
