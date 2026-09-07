#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${FLOATDUDE_DERIVED_DATA_PATH:-$PROJECT_ROOT/.build/product}"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/FloatDude.app"
INSTALLED_APP="/Applications/FloatDude.app"
BUNDLE_ID="com.kks999.FloatDude"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
STAGED_APP="/Applications/.FloatDude.installing.$$.app"
BACKUP_APP="/Applications/.FloatDude.previous.$$.app"
CANDIDATES_FILE="$(mktemp -t floatdude-copies)"

cleanup() {
    rm -f "$CANDIDATES_FILE"
    rm -rf "$STAGED_APP"
}
trap cleanup EXIT

bundle_identifier() {
    "$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

registered_floatdude_paths() {
    "$LSREGISTER" -dump 2>/dev/null \
        | sed -n 's/^[[:space:]]*path:[[:space:]]*\(.*FloatDude\.app\).*/\1/p'
}

collect_existing_copies() {
    local search_root
    mdfind 'kMDItemCFBundleIdentifier == "com.kks999.FloatDude"' 2>/dev/null || true
    for search_root in \
        "$PROJECT_ROOT/.build" \
        "$HOME/Applications" \
        "$HOME/Desktop" \
        "$HOME/Downloads" \
        "$HOME/Library/Developer/Xcode/DerivedData" \
        "/private/tmp"
    do
        if [[ -d "$search_root" ]]; then
            find "$search_root" -type d -name 'FloatDude.app' -prune -print 2>/dev/null || true
            find "$search_root" -type l -name 'FloatDude.app' -print 2>/dev/null || true
        fi
    done
}

unregister_and_remove_other_copies() {
    {
        collect_existing_copies
        registered_floatdude_paths
    } | awk 'NF' | sort -u > "$CANDIDATES_FILE"

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        [[ "$candidate" == "$INSTALLED_APP" ]] && continue

        # Stale Launch Services records can outlive the bundle. Unregister the
        # exact FloatDude path even when the file has already disappeared.
        "$LSREGISTER" -u "$candidate" >/dev/null 2>&1 || true

        if [[ -L "$candidate" ]]; then
            rm -f "$candidate"
            echo "Removed FloatDude link: $candidate"
        elif [[ -d "$candidate" ]] && [[ "$(bundle_identifier "$candidate")" == "$BUNDLE_ID" ]]; then
            rm -rf "$candidate"
            echo "Removed FloatDude copy: $candidate"
        fi
    done < "$CANDIDATES_FILE"
}

echo "Building FloatDude Release app…"
xcodebuild \
    -project "$PROJECT_ROOT/FloatDude.xcodeproj" \
    -scheme FloatDude \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

if [[ "$(bundle_identifier "$BUILT_APP")" != "$BUNDLE_ID" ]]; then
    echo "Built bundle identifier is not $BUNDLE_ID: $BUILT_APP" >&2
    exit 1
fi

rm -rf "$STAGED_APP" "$BACKUP_APP"
ditto "$BUILT_APP" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

# Quit every running FloatDude executable, including a stale build-path copy.
osascript -e 'tell application id "com.kks999.FloatDude" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -f '/FloatDude\.app/Contents/MacOS/FloatDude$' >/dev/null; then
        break
    fi
    sleep 0.2
done
pkill -f '/FloatDude\.app/Contents/MacOS/FloatDude$' >/dev/null 2>&1 || true

if [[ -e "$INSTALLED_APP" || -L "$INSTALLED_APP" ]]; then
    mv "$INSTALLED_APP" "$BACKUP_APP"
fi
if ! mv "$STAGED_APP" "$INSTALLED_APP"; then
    if [[ -e "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$INSTALLED_APP"
    fi
    echo "Could not replace $INSTALLED_APP" >&2
    exit 1
fi

if ! codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"; then
    rm -rf "$INSTALLED_APP"
    if [[ -e "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$INSTALLED_APP"
    fi
    echo "Installed app failed code-signature verification; restored the previous copy." >&2
    exit 1
fi
rm -rf "$BACKUP_APP"

unregister_and_remove_other_copies
"$LSREGISTER" -f "$INSTALLED_APP" >/dev/null

# Remove any remaining stale FloatDude registrations, then force-register the
# installed path once more as the single canonical copy.
registered_floatdude_paths | sort -u > "$CANDIDATES_FILE"
while IFS= read -r registered_path; do
    [[ -n "$registered_path" ]] || continue
    [[ "$registered_path" == "$INSTALLED_APP" ]] && continue
    "$LSREGISTER" -u "$registered_path" >/dev/null 2>&1 || true
done < "$CANDIDATES_FILE"
"$LSREGISTER" -f "$INSTALLED_APP" >/dev/null

remaining_paths="$(registered_floatdude_paths | sort -u)"
unexpected_paths="$(printf '%s\n' "$remaining_paths" | awk -v expected="$INSTALLED_APP" 'NF && $0 != expected')"
if [[ -n "$unexpected_paths" ]]; then
    echo "Unexpected FloatDude Launch Services registrations remain:" >&2
    printf '%s\n' "$unexpected_paths" >&2
    exit 1
fi

open "$INSTALLED_APP"

echo "Installed: $INSTALLED_APP"
echo "SHA-256: $(shasum -a 256 "$INSTALLED_APP/Contents/MacOS/FloatDude" | awk '{print $1}')"
echo "Launch Services path: $remaining_paths"
