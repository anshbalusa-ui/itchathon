#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
simulator=""
output=""
mode=repair
fail() { printf 'Benchmark: %s\n' "$*" >&2; exit 1; }
while (($#)); do
  case "$1" in
    --repo|--simulator|--output|--mode)
      (($# >= 2)) || fail "Missing value for $1"
      case "$1" in --repo) repo="$2";; --simulator) simulator="$2";; --output) output="$2";; --mode) mode="$2";; esac
      shift 2;;
    --help|-h)
      printf '%s\n' 'Usage: Scripts/benchmark_onyou.sh --simulator UDID --output NEW_DIRECTORY [--repo WORKTREE] [--mode repair|baseline]' \
        'Measures saved-fixture cold/warm try-on, real rendered rotation, native Core ML, ring construction and RGB-only preflight rejection.' \
        'Use an idle simulator and a dedicated worktree. No hardware/capture-success claim. No simulator erasure.'
      exit 0;;
    *) fail "Unknown argument: $1";;
  esac
done
[[ -n "$simulator" && -n "$output" ]] || fail 'Supply --simulator and --output; see --help.'
[[ "$mode" == repair || "$mode" == baseline ]] || fail 'Mode must be repair or baseline.'
for command in xcrun xcodebuild xcodegen python3; do command -v "$command" >/dev/null || fail "Required tool missing: $command"; done
[[ -f "$repo/Project.json" && -d "$repo/Tests" ]] || fail 'The target must be the actual On You Project.json worktree.'
[[ ! -e "$output" ]] || fail 'Output must be a new path; existing evidence is never removed.'
repo="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$repo")"
output="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")"
project="$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert "FitCheck" in s["schemes"]; print(s["name"]+".xcodeproj")' "$repo/Project.json")"
probe="$repo/Tests/OnYouPerformanceProbe.swift"
fixtures="$repo/Tests/OnYouPerformanceFixtures"
[[ ! -e "$probe" ]] || fail 'Reserved temporary probe path exists; nothing was overwritten.'
[[ ! -e "$fixtures" ]] || fail 'Reserved temporary fixture path exists; nothing was overwritten.'
mkdir -p "$output"
state="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; ds=[d for a in json.load(sys.stdin)["devices"].values() for d in a if d["udid"]==sys.argv[1] and ".iPhone-" in d.get("deviceTypeIdentifier","")]; assert len(ds)==1,"Available iPhone simulator not found"; print(ds[0]["state"])' "$simulator")"
if [[ "$state" != Booted ]]; then xcrun simctl boot "$simulator"; fi
xcrun simctl bootstatus "$simulator" -b
cleanup() {
  local status=$?
  trap - EXIT
  rm -f -- "$probe"
  rm -rf -- "$fixtures"
  if ! (cd "$repo" && xcodegen generate --spec Project.json) >/dev/null; then
    printf 'Benchmark: failed to regenerate the project after probe cleanup.\n' >&2
    if ((status == 0)); then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT
cp "$here/PerformanceProbe.swift" "$probe"
if [[ "$mode" == baseline ]]; then
  mkdir -p "$fixtures"
  for file in synthetic-avatar-a.usdz synthetic-avatar-b.usdz synthetic-shirt.png synthetic-shirt-coral.png; do
    cp "$here/../DevelopmentAssets/OnYouTryOnFixtures/$file" "$fixtures/probe-$file"
  done
fi
# Keep baseline production/configuration files untouched. Both measurements use
# the same noninteractive test launcher, without requiring debugger permission.
python3 - "$repo/Project.json" "$output/PerformanceProject.json" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    spec = json.load(source)
spec["schemes"]["FitCheck"]["test"]["debugEnabled"] = False
with open(sys.argv[2], "w") as destination:
    json.dump(spec, destination, indent=2)
    destination.write("\n")
PY
(cd "$repo" && xcodegen generate --spec "$output/PerformanceProject.json" --project-root "$repo" --project "$repo")
flags=(CODE_SIGNING_ALLOWED=NO)
if [[ "$mode" == repair ]]; then flags+=('OTHER_SWIFT_FLAGS=$(inherited) -DONYOU_REPAIR_PROBE'); fi
set +e
(cd "$repo" && xcodebuild -project "$project" -scheme FitCheck -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$output/Derived" \
  -resultBundlePath "$output/Performance.xcresult" -parallel-testing-enabled NO \
  -only-testing:FitCheckTests/OnYouPerformanceProbe "${flags[@]}" test -quiet) 2>&1 | tee "$output/build.log"
test_status=${PIPESTATUS[0]}
set -e
if [[ -f "$output/Performance.xcresult/Info.plist" ]]; then
  xcrun xcresulttool get test-results summary --path "$output/Performance.xcresult" > "$output/summary.json"
  xcrun xcresulttool export attachments --path "$output/Performance.xcresult" --output-path "$output/attachments"
fi
printf 'Benchmark %s exit %s; original evidence: %s\n' "$mode" "$test_status" "$output"
exit "$test_status"
