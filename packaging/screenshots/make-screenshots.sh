#!/bin/bash
# Generates the App Store screenshots: 4 scenes in 11 languages, 2880 × 1800.
#
#   packaging/screenshots/make-screenshots.sh [output dir]   (default: docs/app-store/screenshots)
#
# Builds the app for a moment with ScreenshotScenes.swift and a launch hook, opens each scene
# in a new instance, captures only its window and composes background and caption around it.
# The app's sources go back as they were, whatever happens. Windows open on screen for about
# a minute; the Terminal needs Screen Recording permission.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly HERE="$ROOT/packaging/screenshots"
readonly OUT="${1:-$ROOT/docs/app-store/screenshots}"
readonly DELEGATE="$ROOT/Amoxtli/App/AppDelegate.swift"
readonly SCENES="$ROOT/Amoxtli/App/ZZScreenshotScenes.swift"
readonly GUARD='guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }'

die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }

[[ -z "$(git -C "$ROOT" status --porcelain -- "$DELEGATE")" ]] || die "AppDelegate.swift has uncommitted changes"
[[ ! -e "$SCENES" ]] || die "$SCENES already exists"
grep -qF "$GUARD" "$DELEGATE" || die "the launch hook's anchor is gone from AppDelegate.swift; update this script"

RAW="$(mktemp -d)"
restore() {
  rm -f "$SCENES"
  git -C "$ROOT" checkout -q -- "$DELEGATE"
  rm -rf "$RAW"
}
trap restore EXIT

step "Adding the scene hook"
cp "$HERE/ScreenshotScenes.swift" "$SCENES"
# Right after the guard that skips the tests. The flag needs a value: without one, the
# argument parser takes the next flag as its value and a loose "(en)" opens as a document.
HOOK='        if CommandLine.arguments.contains("-ScreenshotScenes") {\
            setvbuf(stdout, nil, _IOLBF, 0)\
            Task { @MainActor in\
                do { try await ScreenshotScenes().run() } catch { print("SHOT missing \\(error)") }\
                NSApp.terminate(nil)\
            }\
            return\
        }'
sed -i '' "/XCTestConfigurationFilePath/a\\
$HOOK
" "$DELEGATE"

step "Building"
xcodebuild -project "$ROOT/Amoxtli.xcodeproj" -scheme Amoxtli -destination 'platform=macOS' -quiet build >"$RAW/build.log" 2>&1 ||
  { grep -E "error:" "$RAW/build.log" >&2 || tail -30 "$RAW/build.log" >&2; die "the build failed"; }
APP="$(xcodebuild -project "$ROOT/Amoxtli.xcodeproj" -scheme Amoxtli -destination 'platform=macOS' -showBuildSettings 2>/dev/null |
  awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/Amoxtli.app"

step "Capturing (windows open on screen for about a minute)"
LOG="$RAW/app.log"
: >"$LOG"
# A new instance, so an Amoxtli that is already open stays as it is.
open -n -a "$APP" --stdout "$LOG" --stderr "$LOG" --args -AppleLanguages "(en)" -AppleLocale en_US -ScreenshotScenes YES
seen=""
for _ in $(seq 1 240); do
  while read -r _ _ name id; do
    case " $seen " in *" $name "*) continue ;; esac
    seen="$seen $name"
    sleep 1.5
    screencapture -x -o -l"$id" "$RAW/raw-$name.png"
    echo "    $name"
  done < <(grep "^SHOT SCENE" "$LOG")
  grep -q "^SHOT DONE\|^SHOT missing" "$LOG" && break
  sleep 0.5
done
grep "^SHOT warning" "$LOG" >&2 || true
grep -q "^SHOT DONE" "$LOG" || die "the scenes did not finish: $(grep '^SHOT missing' "$LOG" || echo 'timed out')"

step "Composing into $OUT"
swift "$HERE/compose.swift" "$RAW" "$OUT"
