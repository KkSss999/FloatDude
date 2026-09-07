#!/usr/bin/env bash

set -euo pipefail

validation_binary=$(mktemp -t floatdude-local-validation)
trap 'rm -f "$validation_binary"' EXIT

source_files=()
while IFS= read -r source_file; do
    source_files+=("$source_file")
done < <(rg --files Sources/FloatDude -g '*.swift' | rg -v 'FloatDudeApp.swift')

swiftc -warnings-as-errors \
    -module-name FloatDudeLocalValidation \
    "${source_files[@]}" \
    Scripts/local-validation.swift \
    -o "$validation_binary"

"$validation_binary"
