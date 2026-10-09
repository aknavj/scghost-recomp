#!/usr/bin/env bash
# Regenerate and patch the recompiled C from Ghost.xbe with the xboxrecomp toolkit
# (../xboxrecomp), in the one order that works. Same shape as hl2/regen.sh.
#
#   xbe_parser    section layout -> build/xr/analysis.json
#   disasm        ALL code sections, never --text-only: without the XDK
#                 sections (D3D, DSOUND, XNET, XPP...) there are no function
#                 boundaries there and each function is glued to the next.
#   func_id       library-function identification (CRT, XDK).
#   abi_analysis  calling convention / params / return type.
#   recomp        emits a split-250 baseline into a staging directory.
#   patch         applies the preserved source repairs before publication.
#
# Nothing here is committed output: build/ and gen/ are regenerable from the
# user's own default.xbe.
#
# Usage: ./regen.sh [--disasm]

set -euo pipefail

SCGHOST="$(cd "$(dirname "$0")" && pwd)"
RECOMP="$SCGHOST/../xboxrecomp"
XBE="$SCGHOST/game/StarCraft Ghost/Ghost.xbe"
OUT="$SCGHOST/build/xr"
GEN="$SCGHOST/src/game/recomp/gen"

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--disasm" ) ]]; then
    echo "Usage: $0 [--disasm]" >&2
    exit 1
fi

if [[ ! -f "$XBE" ]]; then
    echo "missing $XBE -- extract it from your own disc image"
    exit 1
fi
bash "$SCGHOST/patch.sh" --validate
if [[ -L "$GEN" ]]; then
    echo "Refusing to replace a symlinked generated directory: $GEN" >&2
    exit 1
fi
mkdir -p "$OUT"
LOCK="$OUT/regen.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Regeneration is already running, or $LOCK remains from an interrupted run." >&2
    echo "Do not regenerate while compiling. Remove the lock only after checking no generation is active." >&2
    exit 1
fi
STAGE=""
finish() {
    local status=$?
    if ! rmdir "$LOCK"; then
        echo "Cannot remove regeneration lock: $LOCK" >&2
        if [[ $status -eq 0 ]]; then status=1; fi
    fi
    if [[ $status -ne 0 && -n "$STAGE" ]]; then
        echo "Regeneration failed; staged diagnostics are retained at $STAGE." >&2
        echo "Check the retained staging directory and any reported backup before rebuilding." >&2
    fi
    exit "$status"
}
trap finish EXIT
STAGE="$(mktemp -d "$OUT/regen.XXXXXX")"
# recomp runs from the toolkit dir, so a relative trace list must be absolutised.
if [[ -n "${TRACE_FUNCS:-}" && "$TRACE_FUNCS" != /* ]]; then
    TRACE_FUNCS="$SCGHOST/$TRACE_FUNCS"
fi

SEEDS=()
[[ -f "$SCGHOST/config/seed_functions.json" ]] && \
    SEEDS=(--seed-functions "$SCGHOST/config/seed_functions.json")

FORCE=()
[[ "${1:-}" == "--disasm" ]] && FORCE=(--force)
echo "==> xbe_parser"
(cd "$RECOMP" && py -3 -m tools.xbe_parser "$XBE" \
    --json "$OUT/analysis.json" --quiet) || exit 1

# The disassembler cache checks the binary and seed set, including seed removal.
echo "==> disasm"
(cd "$RECOMP" && py -3 -m tools.disasm "$XBE" \
    --analysis-json "$OUT/analysis.json" "${SEEDS[@]}" "${FORCE[@]}" \
    -o "$OUT/disasm" -v) > "$OUT/disasm.log" 2>&1 || { tail -20 "$OUT/disasm.log"; exit 1; }
tr '\r' '\n' < "$OUT/disasm.log" | grep -E "Cache hit|Total functions|Reachable|Seeded" || true

echo "==> func_id"
(cd "$RECOMP" && py -3 -m tools.func_id "$XBE" \
    --functions "$OUT/disasm/functions.json" \
    --strings   "$OUT/disasm/strings.json" \
    --xrefs     "$OUT/disasm/xrefs.json" \
    -o "$OUT/func_id" | tail -1) || exit 1

echo "==> abi_analysis"
(cd "$RECOMP" && py -3 -m tools.abi_analysis "$XBE" \
    --functions  "$OUT/disasm/functions.json" \
    --identified "$OUT/func_id/identified_functions.json" \
    --output-dir "$OUT/abi" | tail -1) || exit 1

echo "==> recomp"
if ! (cd "$RECOMP" && py -3 -m tools.recomp "$XBE" --all --split 250 \
    --disasm-dir  "$OUT/disasm" \
    --func-id-dir "$OUT/func_id" \
    --abi-dir     "$OUT/abi" \
    --exclude-manual "$SCGHOST/src/recomp_manual.c" \
    ${TRACE_FUNCS:+--trace-functions "$TRACE_FUNCS"} \
    --gen-dir     "$STAGE/src/game/recomp/gen" \
    -o "$STAGE/recomp"
) > "$STAGE/recomp.log" 2>&1; then
    tail -25 "$STAGE/recomp.log" >&2
    exit 1
fi
grep -aE "unresolved|functions \(|Complete" "$STAGE/recomp.log" || true

echo "==> patching staged sources"
bash "$SCGHOST/patch.sh" --root "$STAGE"
NEW="$STAGE/src/game/recomp/gen"
for required in recomp_dispatch.c recomp_funcs.h recomp_types.h recomp_overrides.h recomp_preserved.c; do
    if [[ ! -f "$NEW/$required" ]]; then
        echo "Patched output is incomplete: missing $required" >&2
        exit 1
    fi
done

BACKUP=""
if [[ -d "$GEN" ]]; then
    mkdir -p "$SCGHOST/build/regen-backups"
    BACKUP="$(mktemp -d "$SCGHOST/build/regen-backups/$(date +%Y%m%d-%H%M%S).XXXXXX")"
    rmdir "$BACKUP"
    mv "$GEN" "$BACKUP"
elif [[ -e "$GEN" ]]; then
    echo "Generated path is not a directory: $GEN" >&2
    exit 1
fi
mkdir -p "$(dirname "$GEN")"
if ! mv "$NEW" "$GEN"; then
    if [[ -n "$BACKUP" ]]; then
        if ! mv "$BACKUP" "$GEN"; then
            echo "Cannot restore generated sources; recover them from $BACKUP before building." >&2
        fi
    fi
    exit 1
fi
if [[ -n "$BACKUP" ]]; then
    echo "==> previous generated sources backed up at $BACKUP"
fi
echo "==> generated and patched sources published; diagnostics at $STAGE"
echo "==> done. Now: cmake -S . -B build-xr && cmake --build build-xr --config Release"