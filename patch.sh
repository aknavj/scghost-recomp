#!/usr/bin/env bash
# Usage: ./patch.sh [--check]
# Apply patches/generated.patch to the generated game sources.

set -euo pipefail

SCGHOST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$SCGHOST/patches/generated.patch"

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 1
fi

if [[ ! -f "$PATCH" ]]; then
    echo "Missing patch: $PATCH" >&2
    exit 1
fi

cd "$SCGHOST"
echo "==> checking patch"
git apply --check --whitespace=nowarn "$PATCH"

if [[ "${1:-}" == "--check" ]]; then
    echo "==> patch can be applied; no files changed"
    exit 0
fi

echo "==> applying patch"
git apply --whitespace=nowarn "$PATCH"
echo "==> done. Now: cmake --build build-xr --config Release"
