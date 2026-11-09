#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/launch_friday_demo.sh [--simulator UDID] [--app PATH] [--derived-data PATH]

Builds and launches the Debug Friday visual demo on an iPhone Simulator. By
 default, prefers a booted iPhone, then the first available iPhone. Use --app
 to install an existing Debug simulator app bundle (Release bundles are rejected).
Derived data is stored outside the repository by default.
EOF
}

fail() {
  printf 'launch_friday_demo: %s\n' "$*" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SIMULATOR=""
APP=""
DERIVED_DATA="${TMPDIR:-/tmp}/FitCheckFridayDemoDerived"
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --simulator)
      (($# >= 2)) || fail '--simulator requires a UDID'
      SIMULATOR="$2"; shift 2 ;;
    --app)
      (($# >= 2)) || fail '--app requires an .app path'
      APP="$2"; shift 2 ;;
    --derived-data)
      (($# >= 2)) || fail '--derived-data requires a path'
      DERIVED_DATA="$2"; shift 2 ;;
    *) fail "unknown argument: $1 (use --help)" ;;
  esac
done

for command in xcrun xcodebuild python3; do
  command -v "$command" >/dev/null 2>&1 || fail "required tool not found: $command"
done
if [[ -z "$APP" ]]; then
  command -v xcodegen >/dev/null 2>&1 || fail 'required tool not found: xcodegen'
fi

DEVICES="$(xcrun simctl list devices available --json)" || fail 'could not query available simulators'
if [[ -z "$SIMULATOR" ]]; then
  SIMULATOR="$(printf '%s' "$DEVICES" | python3 -c 'import json,sys; d=json.load(sys.stdin); devices=[x for group in d["devices"].values() for x in group if x.get("isAvailable") and x.get("name", "").startswith("iPhone")]; devices.sort(key=lambda x:(x.get("state") != "Booted", x.get("name", ""), x.get("udid", ""))); print(devices[0]["udid"] if devices else "")')" || fail 'could not select an iPhone simulator'
fi
[[ -n "$SIMULATOR" ]] || fail 'no available iPhone simulator found'
printf '%s' "$DEVICES" | python3 -c 'import json,sys; d=json.load(sys.stdin); u=sys.argv[1]; ok=any(x.get("udid")==u and x.get("isAvailable") and x.get("name", "").startswith("iPhone") for group in d["devices"].values() for x in group); sys.exit(0 if ok else 1)' "$SIMULATOR" || fail "simulator is not an available iPhone: $SIMULATOR"

if [[ -z "$APP" ]]; then
  xcodebuild -version || fail 'xcodebuild could not report its version'
  xcodegen --version || fail 'xcodegen could not report its version'
  DERIVED_DATA="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$DERIVED_DATA")" || fail 'could not resolve derived-data path'
  case "$DERIVED_DATA/" in "$ROOT/"*) fail 'derived data must be outside the repository' ;; esac
  mkdir -p "$DERIVED_DATA"
  (cd "$ROOT" && xcodegen generate) || fail 'xcodegen project generation failed'
  (cd "$ROOT" && xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
    -sdk iphonesimulator -destination "platform=iOS Simulator,id=$SIMULATOR" \
    -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build) || fail 'Debug simulator build failed'
  APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/FitCheck.app"
fi

[[ -d "$APP" ]] || fail "app bundle not found: $APP"
APP="$(cd "$APP" && pwd -P)"
python3 - "$APP" <<'PY' || fail 'app is not a current Debug FitCheck simulator build with the measurement avatar demo'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
try:
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.itchathon.fitcheck":
        sys.exit(1)
    if "iPhoneSimulator" not in info.get("CFBundleSupportedPlatforms", []):
        sys.exit(1)
    executable = app / info["CFBundleExecutable"]
    binaries = [executable, app / (executable.name + ".debug.dylib")]
    payloads = [path.read_bytes() for path in binaries if path.is_file()]
    if not all(any(marker in data for data in payloads)
               for marker in (b"-fitcheck-demo-internal", b"HumanShowcaseModel",
                              b"MeasurementAvatarGenerator", b"demo.open-measurements")):
        sys.exit(1)
except (OSError, KeyError, plistlib.InvalidFileException):
    sys.exit(1)
# The development fixture is staged only by the Debug build phase.
assets = app / "FitCheckDevelopmentAssets" / "FitCheckGeometricVest.fitmesh"
if not assets.is_file():
    sys.exit(1)
human = app / "HumanShowcase"
if not all((human / name).is_file() for name in ("human-showcase-v1.bin", "LICENSE.txt", "NOTICE.txt")):
    sys.exit(1)
PY

STATE="$(xcrun simctl list devices | python3 -c 'import sys; u=sys.argv[1]; lines=sys.stdin.readlines(); print(next((line for line in lines if u in line), ""))' "$SIMULATOR")"
if [[ "$STATE" != *"(Booted)"* ]]; then
  xcrun simctl boot "$SIMULATOR" || fail "could not boot simulator $SIMULATOR"
fi
xcrun simctl bootstatus "$SIMULATOR" -b || fail 'simulator did not finish booting'
xcrun simctl install "$SIMULATOR" "$APP" || fail 'could not install demo app'
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" || fail 'app bundle identifier is missing'
xcrun simctl launch --terminate-running-process "$SIMULATOR" "$BUNDLE_ID" -fitcheck-demo-internal || fail 'could not launch the internal demo'
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR" || fail 'could not open Simulator'
printf 'Friday demo launched on simulator %s\n' "$SIMULATOR"
