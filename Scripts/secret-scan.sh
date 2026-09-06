#!/usr/bin/env bash

set -euo pipefail

pattern='sk-[A-Za-z0-9]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{20,}|-----BEGIN[[:space:]][A-Z ]*PRIVATE KEY-----|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{20,}|api[_-]?key["'"']?[[:space:]]*[:=][[:space:]]*["'"'][A-Za-z0-9._~-]{16,}["'"']'

if [[ "${1:-}" == "--staged" ]]; then
    while IFS= read -r -d '' path; do
        if rg -n -I -e "$pattern" -- "$path" >/dev/null 2>&1; then
            printf 'secret-like credential pattern found in staged path: %s\n' "$path" >&2
            exit 1
        fi
    done < <(git diff --cached --name-only --diff-filter=ACMR -z)
else
    while IFS= read -r -d '' path; do
        if rg -n -I -e "$pattern" -- "$path" >/dev/null 2>&1; then
            printf 'secret-like credential pattern found in path: %s\n' "$path" >&2
            exit 1
        fi
    done < <(git ls-files --cached --others --exclude-standard -z)
fi

printf 'secret scan passed\n'
