#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/launch_onyou.sh [--simulator UDID] [--app PATH] [--derived-data PATH]
                             [--fixtures [--body a|b] [--scenario NAME]]

Builds unsigned Debug from the actual Project.json and opens On You in Simulator.
--fixtures uses isolated, visibly synthetic saved-avatar/closet data in the REAL
app screens. It never simulates a completed camera scan or alters personal stores.
Scenarios: valid, missing-avatar, photo-only, missing-photo, unusable-pose.
No simulator erasure, signing credentials or physical device is required.
EOF
}
fail() { printf 'launch_onyou: %s\n' "$*" >&2; exit 1; }
native() {
  "$PYTHON" - "$@" <<'PY'
import subprocess, sys
seconds = int(sys.argv[1])
process = subprocess.Popen(sys.argv[2:])
try:
    sys.exit(process.wait(timeout=seconds))
except subprocess.TimeoutExpired:
    process.kill()
    print("launch_onyou: native command timed out after %ss: %s. No simulator data was erased; the app may remain installed." % (seconds, sys.argv[2]), file=sys.stderr)
    sys.exit(124)
PY
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Xcode supplies this interpreter; do not depend on an unrelated Homebrew/venv.
PYTHON=/usr/bin/python3
SIMULATOR=""; APP=""; FIXTURES=0; BODY=a; SCENARIO=valid
DERIVED="${TMPDIR:-/tmp}/OnYouRepairDerived"
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --simulator) (($# >= 2)) || fail 'missing simulator UDID'; SIMULATOR="$2"; shift 2 ;;
    --app) (($# >= 2)) || fail 'missing Debug .app path'; APP="$2"; shift 2 ;;
    --derived-data) (($# >= 2)) || fail 'missing derived-data path'; DERIVED="$2"; shift 2 ;;
    --fixtures) FIXTURES=1; shift ;;
    --body) (($# >= 2)) || fail 'missing body fixture'; BODY="$2"; shift 2 ;;
    --scenario) (($# >= 2)) || fail 'missing fixture scenario'; SCENARIO="$2"; shift 2 ;;
    *) fail "unknown option: $1 (use --help)" ;;
  esac
done
case "$BODY" in a|b) ;; *) fail '--body must be a or b' ;; esac
case "$SCENARIO" in valid|missing-avatar|photo-only|missing-photo|unusable-pose) ;; *) fail 'unknown fixture scenario' ;; esac
if [[ "$FIXTURES" = 0 && ( "$BODY" != a || "$SCENARIO" != valid ) ]]; then fail 'fixture options require --fixtures'; fi
for command in xcrun xcodebuild "$PYTHON"; do command -v "$command" >/dev/null || fail "required tool missing: $command"; done
PROJECT_NAME="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$ROOT/Project.json")"
PRODUCT_NAME="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["targets"]["FitCheck"]["settings"]["PRODUCT_NAME"])' "$ROOT/Project.json")"
BUNDLE_ID="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["targets"]["FitCheck"]["settings"]["PRODUCT_BUNDLE_IDENTIFIER"])' "$ROOT/Project.json")"
DEVICES="$(native 30 xcrun simctl list devices available --json)" || fail 'could not list simulators'
SIMULATOR="$(printf '%s' "$DEVICES" | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); p=[x for g in d["devices"].values() for x in g if x.get("isAvailable") and x.get("deviceTypeIdentifier", "").split(".")[-1].startswith("iPhone")]; p.sort(key=lambda x:(x["state"]!="Booted",x["name"],x["udid"])); u=sys.argv[1] or (p[0]["udid"] if p else ""); assert any(x["udid"]==u for x in p), "No matching available iPhone simulator"; print(u)' "$SIMULATOR")" || fail 'select an available iPhone with --simulator'
if [[ -z "$APP" ]]; then
  command -v xcodegen >/dev/null || fail 'required tool missing: xcodegen'
  DERIVED="$("$PYTHON" -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$DERIVED")"
  case "$DERIVED/" in "$ROOT/"*) fail 'derived data must be outside Git' ;; esac
  (cd "$ROOT" && native 60 xcodegen generate --spec Project.json && native 900 xcodebuild -project "$PROJECT_NAME.xcodeproj" -scheme FitCheck -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$SIMULATOR" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build -quiet) || fail 'current Debug simulator build failed'
  APP="$DERIVED/Build/Products/Debug-iphonesimulator/$PRODUCT_NAME.app"
fi
[[ -d "$APP" ]] || fail "app bundle not found: $APP"
"$PYTHON" - "$APP" "$BUNDLE_ID" <<'PY' || fail 'not a current On You Debug simulator app'
import pathlib, plistlib, sys
app=pathlib.Path(sys.argv[1]).resolve()
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']==sys.argv[2]
assert 'iPhoneSimulator' in info['CFBundleSupportedPlatforms']
executable=info['CFBundleExecutable']
files=[app/executable, app/(executable+'.debug.dylib')]
data=[p.read_bytes() for p in files if p.is_file()]
assert all(any(marker in payload for payload in data) for marker in (b'-onyou-tryon-fixture',b'OnYouTryOnFixtures',b'TryOnBuilder'))
for name in ('synthetic-avatar-a.usdz','synthetic-avatar-b.usdz','synthetic-shirt.png','synthetic-shirt-coral.png','unsupported-pose.usdz'):
    assert (app/'OnYouTryOnFixtures'/name).is_file()
PY
STATE="$(printf '%s' "$DEVICES" | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(next(x["state"] for g in d["devices"].values() for x in g if x["udid"]==sys.argv[1]))' "$SIMULATOR")"
if [[ "$STATE" != Booted ]]; then native 60 xcrun simctl boot "$SIMULATOR" || fail 'simulator boot failed'; fi
native 300 xcrun simctl bootstatus "$SIMULATOR" -b || fail 'simulator did not finish booting'
native 300 xcrun simctl install "$SIMULATOR" "$APP" || fail 'installation failed; existing simulator data was not erased'
ARGS=("$SIMULATOR" "$BUNDLE_ID")
if [[ "$FIXTURES" = 1 ]]; then ARGS+=(-onyou-tryon-fixture "-onyou-fixture-body=$BODY" "-onyou-fixture-scenario=$SCENARIO"); fi
native 60 xcrun simctl launch --terminate-running-process "${ARGS[@]}" || fail 'On You launch failed'
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR" || fail 'app launched, but graphical Simulator could not open'
printf 'On You launched on %s (synthetic fixtures: %s)\n' "$SIMULATOR" "$FIXTURES"
