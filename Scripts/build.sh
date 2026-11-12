#!/bin/bash
# Build "LTE Modem Stats.app" (menu bar only, no Dock icon).
#
#   Scripts/build.sh              release build → build/LTE Modem Stats.app
#   Scripts/build.sh --test       also run the unit tests
#   Scripts/build.sh --install    also install to /Applications, link the CLI into
#                                 ~/.local/bin and restart the menu bar app
#
# Options combine: Scripts/build.sh --test --install
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT="lte-modem-stats"
APP_NAME="LTE Modem Stats.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
CLI_DIR="$HOME/.local/bin"
CLI_LINK="$CLI_DIR/$PRODUCT"

RUN_TESTS=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --test) RUN_TESTS=1 ;;
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
step() { printf '\n==> %s\n' "$*"; }

# The Command Line Tools sometimes fail to load a macro plugin through swift-plugin-server
# ("plugin for module '…' not found"); that run is retried, other errors are not.
swift_retry() {
  local log status
  log="$(mktemp)"
  for attempt in 1 2 3; do
    "$@" >"$log" 2>&1 && status=0 || status=$?
    if [ "$status" = 0 ]; then
      tail -n 3 "$log"
      rm -f "$log"
      return 0
    fi
    if grep -q "plugin for module '.*' not found" "$log" && [ "$attempt" -lt 3 ]; then
      echo "   (macro plugin failed to load, retrying $((attempt + 1))/3)"
      continue
    fi
    # Strip colors, keep one copy of each top-level error line.
    sed $'s/\x1b\\[[0-9;]*m//g' "$log" | grep -E 'error:|✘' | grep -v '^[ |]' | awk '!seen[$0]++' | head -n 20 >&2 \
      || tail -n 40 "$log" >&2
    rm -f "$log"
    return "$status"
  done
}

if [ "$RUN_TESTS" = 1 ]; then
  step "Running tests"
  # Load the swift-testing macros into the compiler itself: the out-of-process
  # swift-plugin-server route fails intermittently with the Command Line Tools.
  TEST_FLAGS=()
  TESTING_MACROS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
  if [ -f "$TESTING_MACROS" ]; then
    TEST_FLAGS=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_MACROS")
  fi
  # ${a[@]+…}: bash 3.2 (macOS /bin/bash) treats an empty array as unbound under `set -u`.
  swift_retry swift test ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"}
fi

step "Building release"
swift_retry swift build -c release --product "$PRODUCT"
BIN="$(swift build -c release --show-bin-path)/$PRODUCT"

step "Assembling $APP_NAME $VERSION"
APP="$ROOT/build/$APP_NAME"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$PRODUCT"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" \
  "$ROOT/Packaging/Info.plist" >"$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Ad hoc signature: required to run on Apple Silicon; also seals Info.plist and resources.
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "   $APP"

step "Smoke test"
"$APP/Contents/MacOS/$PRODUCT" help >/dev/null
echo "   ok"

if [ "$INSTALL" = 0 ]; then
  echo
  echo "Done. Open it with: open \"$APP\"   (or install with: Scripts/build.sh --install)"
  exit 0
fi

# /Applications is writable for admin users; otherwise use ~/Applications.
APPS_DIR="/Applications"
[ -w "$APPS_DIR" ] || APPS_DIR="$HOME/Applications"
TARGET="$APPS_DIR/$APP_NAME"
step "Installing to $TARGET"
# Quit the running menu bar app first (it saves traffic history on SIGTERM).
if pkill -TERM -x "$PRODUCT"; then
  for _ in $(seq 50); do pgrep -x "$PRODUCT" >/dev/null || break; sleep 0.1; done
  echo "   stopped the running menu bar app"
fi
mkdir -p "$APPS_DIR"
# Replace the bundle as a whole (new files, never overwritten in place, so the
# kernel never checks new code against a cached signature of the old one).
rm -rf "$TARGET"
ditto "$APP" "$TARGET"
codesign --verify --strict "$TARGET"

# CLI: `lte-modem-stats status` etc. run the executable inside the app.
mkdir -p "$CLI_DIR"
rm -f "$CLI_LINK"
ln -s "$TARGET/Contents/MacOS/$PRODUCT" "$CLI_LINK"
echo "   CLI: $CLI_LINK → app"

step "Starting the menu bar app"
open "$TARGET"
for _ in $(seq 30); do pgrep -x "$PRODUCT" >/dev/null && break; sleep 0.1; done
if pgrep -x "$PRODUCT" >/dev/null; then
  echo "   running (pid $(pgrep -x "$PRODUCT"))"
else
  echo "   failed to start; try: open \"$TARGET\"" >&2
  exit 1
fi

case ":$PATH:" in
  *":$CLI_DIR:"*) ;;
  *) echo; echo "Note: $CLI_DIR is not in PATH; add it to use '$PRODUCT status' etc." ;;
esac
echo
echo "Done."
