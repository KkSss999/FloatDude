#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
preview_dir=$(mktemp -d -t floatdude-glass-preview)
trap 'rm -rf "$preview_dir"' EXIT
mkdir -p "$preview_dir/FloatDudeGlassPreview.app/Contents/MacOS"
cat > "$preview_dir/FloatDudeGlassPreview.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.floatdude.glass-preview</string>
<key>CFBundleExecutable</key><string>FloatDudeGlassPreview</string>
<key>CFBundleName</key><string>FloatDude Glass Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
source_files=()
while IFS= read -r source_file; do
    source_files+=("$source_file")
done < <(rg --files Sources/FloatDude -g '*.swift' | rg -v 'FloatDudeApp.swift')
swiftc -warnings-as-errors -module-name FloatDudeGlassPreview \
    "${source_files[@]}" Scripts/glass-preview.swift -o "$preview_dir/FloatDudeGlassPreview.app/Contents/MacOS/FloatDudeGlassPreview"
"$preview_dir/FloatDudeGlassPreview.app/Contents/MacOS/FloatDudeGlassPreview"
