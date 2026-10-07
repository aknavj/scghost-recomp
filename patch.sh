#!/usr/bin/env bash
# Usage: ./patch.sh [--check | --validate] [--root DIRECTORY]
# Apply the complete patches/generated/series to the generated game sources.

set -euo pipefail

SCGHOST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$SCGHOST/patches/generated"
SERIES="$PATCH_DIR/series"
ROOT="$SCGHOST"
CHECK=0
VALIDATE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK=1; shift ;;
        --validate) VALIDATE=1; shift ;;
        --root)
            if [[ $# -lt 2 ]]; then
                echo "--root requires a directory" >&2
                exit 1
            fi
            ROOT="$(cd "$2" && pwd)"
            shift 2 ;;
        *) echo "Usage: $0 [--check | --validate] [--root DIRECTORY]" >&2; exit 1 ;;
    esac
done

if [[ "$CHECK" -eq 1 && "$VALIDATE" -eq 1 ]]; then
    echo "--check and --validate cannot be combined" >&2
    exit 1
fi
if [[ ! -f "$SERIES" ]]; then
    echo "Missing patch series: $SERIES" >&2
    exit 1
fi

PATCHES=()
declare -A MEMBERS=()
while IFS= read -r entry || [[ -n "$entry" ]]; do
    entry="${entry%$'\r'}"
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    if [[ ! "$entry" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.patch$ ]]; then
        echo "Invalid patch series member: $entry" >&2
        exit 1
    fi
    if [[ -n "${MEMBERS[$entry]:-}" ]]; then
        echo "Duplicate patch series member: $entry" >&2
        exit 1
    fi
    if [[ ! -s "$PATCH_DIR/$entry" ]]; then
        echo "Missing or empty patch series member: $PATCH_DIR/$entry" >&2
        exit 1
    fi
    if grep -q '^version https://git-lfs.github.com/spec/v1' "$PATCH_DIR/$entry"; then
        echo "Patch series member is an LFS pointer, not a patch: $entry" >&2
        exit 1
    fi
    if ! grep -q '^diff --git ' "$PATCH_DIR/$entry"; then
        echo "Patch series member has no Git diff: $entry" >&2
        exit 1
    fi
    MEMBERS[$entry]=1
    PATCHES+=("$PATCH_DIR/$entry")
done < "$SERIES"
if [[ ${#PATCHES[@]} -eq 0 ]]; then
    echo "Patch series is empty: $SERIES" >&2
    exit 1
fi
shopt -s nullglob
for member in "$PATCH_DIR"/*.patch; do
    if [[ -z "${MEMBERS[${member##*/}]:-}" ]]; then
        echo "Patch is not listed in the series: $member" >&2
        exit 1
    fi
done
if [[ "$VALIDATE" -eq 1 ]]; then
    echo "==> patch series validated (${#PATCHES[@]} members); no sources changed"
    exit 0
fi

cd "$SCGHOST"
APPLY=(git apply --whitespace=nowarn)
if [[ "$ROOT" != "$SCGHOST" ]]; then
    if [[ "$ROOT" != "$SCGHOST/"* ]]; then
        echo "Patch root must be within $SCGHOST" >&2
        exit 1
    fi
    APPLY+=(--directory="${ROOT#"$SCGHOST/"}")
fi
# A single Git apply transaction preserves all-or-nothing behavior across members.
PATCH="$(mktemp)"
trap 'rm -f "$PATCH"' EXIT
cat "${PATCHES[@]}" > "$PATCH"
if "${APPLY[@]}" --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "==> source patchset is already applied; no files changed"
    exit 0
fi
echo "==> checking complete patch series (${#PATCHES[@]} members)"
"${APPLY[@]}" --check "$PATCH"

if [[ "$CHECK" -eq 1 ]]; then
    echo "==> patch can be applied; no files changed"
    exit 0
fi

echo "==> applying patch"
"${APPLY[@]}" "$PATCH"
echo "==> source patchset applied successfully"
