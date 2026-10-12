# StarCraft: Ghost (Release) - Xbox Recomp

Static recompilation of the Xbox StarCraft: Ghost executable using
[XboxRecomp](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/README.md).

The project translates the original x86 game code into C and links it with
the XboxRecomp runtime to produce a native Windows executable. It is a
work-in-progress port, not a complete or verified replacement for the original
Xbox runtime. Successful compilation does not establish gameplay compatibility
or playable performance.

## Port Progress

| Feature | Status | Notes |
| --- | --- | --- |
| Video playback | Partial | Videos play; occasional intro tearing remains. |
| Menu scene | Verified | Character, room and logo effects display correctly. |
| Controller input | Verified | Physical controller works; full menu navigation verified. |
| Loading screen | Partial | Briefings and mission loads exercised; loading-background fidelity not fully verified. |
| Gameplay | Partial | Gameplay and repeated mission changes work in the tested sequence; full campaign compatibility remains unverified. |
| Mission transitions | Verified workload | Three level changes, a mission reload and return to the menu tested; the longer repeat run also passed. |
| Audio | Partial | Intro and gameplay sound work; occasional crackles and incomplete DSP effects remain. |
| Rendering | Partial | Hardware rendering works; texture and shader support remains incomplete. |
| Performance | Partial | Repeated Release mission changes tested without progressive FPS loss; frame rate remains scene-dependent. |

The latest transition fixes address contiguous-memory exhaustion, concurrent
XACT teardown and texture-cache churn. Verification covers the exercised
missions and reload sequence, not every mission, save/load path or rendering
effect. Earlier Debug-menu measurements are not a Release performance baseline.

## Requirements

- Windows x64.
- Visual Studio 2022 with **Desktop development with C++** and a Windows SDK.
- CMake 3.20 or newer.
- Git for Windows, including Git Bash.
- Python 3.10 or newer with the Windows `py` launcher.
- The Python dependencies required by XboxRecomp, including `capstone`.
- [aknavj/xboxrecomp](https://github.com/aknavj/xboxrecomp/tree/modded-software-aknavj-rebased)
  checked out on the **`modded-software-aknavj-rebased` branch**.
- Your own legally obtained game executable and extracted data files.

**The `modded-software-aknavj-rebased` toolkit branch is required for correct behavior.** It
is the supported integration branch; the default branch is not a supported
substitute. The local toolkit checkout must also include the current
thread-local IRQL, memory-reclamation and texture-cache index fixes described
below. A branch name alone does not establish that those fixes are present.

To clone the required branch beside this project, run from the parent directory:

```powershell
git clone --branch modded-software-aknavj-rebased https://github.com/aknavj/xboxrecomp.git xboxrecomp
```

For an existing clone of that fork, preserve any local changes before switching:

```powershell
git -C ..\xboxrecomp fetch origin
git -C ..\xboxrecomp switch modded-software-aknavj-rebased
```

Install Capstone for the Python interpreter used by the regeneration script:

```powershell
py -3 -m pip install capstone
```

Game files are not supplied by this project.

## Directory Layout

Keep the game project and toolkit next to each other:

```text
workspace\
  scghost\
    CMakeLists.txt
    regen.sh
    patch.sh
    game\
      StarCraft Ghost\
        Ghost.xbe
    patches\
      generated\
        series
        recomp_0000.c.patch
        ...
    src\
      main.c
      recomp_manual.c
      game\recomp\gen\
  xboxrecomp\
    game_files\
      Ghost.xbe
      ... extracted game data ...
```

There are currently two separate game-file locations:

| Purpose | Location |
| --- | --- |
| Recompilation input | `game\StarCraft Ghost\Ghost.xbe` inside this project |
| Runtime executable and data | `game_files\` inside the XboxRecomp toolkit |

[regen.sh](regen.sh) reads the first location. [CMakeLists.txt](CMakeLists.txt)
configures the runtime paths from `XBOXRECOMP_DIR\game_files`, through
[game_paths.h.in](src/game_paths.h.in). Put the same executable in both
locations, and keep the extracted data directory structure intact.

The runtime's load-error dialog still mentions `default.xbe` and a `game`
directory. The configured runtime path is `game_files\Ghost.xbe`; use the
printed path in the startup log when diagnosing a missing file.

## Generate the Game Code

Run these commands from the `scghost` directory in **Git Bash**:

```bash
bash regen.sh
```

The script runs the following XboxRecomp tools:

1. XBE parser.
2. Disassembler.
3. Library-function identification.
4. ABI analysis.
5. C recompilation.
6. Checked application of the preserved generated-source patchset.

Analysis and regeneration logs are written under `build\xr`. Generated C
sources and headers are written to `src\game\recomp\gen` and are ignored by Git.
Translation uses `--all --split 250`, producing the same chunk layout expected
by the source patchset. Generation and patching run in a fresh staging directory
under `build\xr`; the live generated tree is replaced only after both succeed.
The previous tree is moved to a uniquely named directory under
`build\regen-backups` before publication.

Existing disassembly is reused. To rebuild it:

```bash
bash regen.sh --disasm
```

If regeneration or patching fails, the existing generated sources remain in
place. The script reports the staging directory containing the translation
log and partial output. Check it or `build\xr\disasm.log`, resolve the error,
and rerun. Do not regenerate while compiling. A lock prevents simultaneous
regeneration; after an abrupt interruption, remove `build\xr\regen.lock` only
after confirming no regeneration process is active.

## Apply the Generated-Code Patch

Normal regeneration applies the patch automatically. To verify an existing
patched tree, or apply the patch to a matching unpatched split-250 baseline,
run in **Git Bash**:

```bash
bash patch.sh --check
bash patch.sh
```

[patch.sh](patch.sh) loads the ordered [series](patches/generated/series) and
checks the complete patchset before changing files. `--check` performs baseline
applicability validation only. `--validate` checks the series and member files
without requiring generated sources. The script can be called from another directory because it resolves paths relative to its own location.

Each file in [patches/generated](patches/generated) patches one generated target:
numbered C chunks, dispatch, declarations, overrides or preserved functions.
The files are ordinary text patches, not LFS payloads. Add new members to
`series`; missing, empty, duplicate, unlisted or LFS-pointer members are rejected.
Other patches directly under `patches` are not automatically applied.
Git line-ending conversion is disabled for these patches to preserve the exact
line endings embedded in their source hunks; do not normalize the patch files.

The script combines the ordered members into one temporary Git apply
transaction. A failure in any member prevents the entire patchset from being
applied; there is no partially applied prefix. Applying the patchset twice
reports that it is already applied rather than modifying the tree again.
`--root DIRECTORY` selects a staging root inside this project;
the relative target remains `src\game\recomp\gen`.

The patchset must match the generated baseline; it is not a general-purpose patch for
arbitrary XBE versions or toolkit output. Changes to the toolkit's generated
output may require rebasing the patch. A mismatched patch is an error, not a
reason to force application or skip repairs. With the same XBE, toolkit and
generation settings, the baseline plus patch reproduces the validated generated
source bytes. This does not promise identical executable bytes across different
compilers, SDKs, build configurations or absolute build paths.

## Configure and Build

Run from the `scghost` directory in **PowerShell**, after generation and
patching:

```powershell
cmake -S . -B build-xr -G "Visual Studio 17 2022" -A x64
cmake --build build-xr --config Release --parallel 2
```

CMake builds the XboxRecomp libraries and the `Ghost` executable. Generated
source files are large, so compilation can take considerable time.

## Run

Launch the Release executable from PowerShell:

```powershell
.\build-xr\Release\Ghost.exe
```

Use a physical controller for the verified input path. Keyboard input is
disabled by default; see the input documentation below for configuration.
Runtime asset paths are configured at build time, so changing the working
directory does not change the configured `game_files` location.

The executable writes `Ghost-run.log` and `Ghost-errors.log` beside itself
(`build-xr\Release` for the command above). Preserve both before starting
another diagnostic run.

### Runtime Defaults

These defaults are applied before runtime initialization by
[main.c](src/main.c):

| Setting | Default | Purpose |
| --- | --- | --- |
| `RECOMP_HEAP_RECLAIM` | `1` | Reuse freed heap and contiguous allocations across mission changes. |
| `RECOMP_TITLE_KEVENTS` | `1` | Support events initialized directly in guest memory, including D3D fence events. |
| `RECOMP_APU_DIAG` | `0` | Disable verbose audio diagnostics during normal play. |
| `RECOMP_FB_SCALE` | `1` | Use the native framebuffer scale. |
| `RECOMP_FB_D3D11` | `0` | Keep the default framebuffer presentation path. |
| `RECOMP_KEYBOARD` | `0` | Keep keyboard input disabled unless explicitly enabled. |
| `RECOMP_WATCHDOG_SECS` | Forced to `0` | Disable timed process termination, including inherited timeout settings. |

Explicit environment settings are preserved except for the timed watchdog,
which Ghost always disables. Native GPU fences and vblank delivery remain
enabled; disabling the watchdog does not bypass guest synchronization.

For non-terminating stall diagnostics:

```powershell
$env:RECOMP_STALL_DUMP = '1'
.\build-xr\Release\Ghost.exe
```

If the game stalls, leave it open long enough to capture the diagnostic output
and preserve the logs. This option does not terminate the process or repair
the stalled guest state.

## Validation

The Release build and targeted runtime regressions passed:

- Startup defaults, explicit overrides, guest-event support and disabled timed
  watchdog behavior.
- Contiguous reclamation through 900 MiB of allocation churn using an
  approximately 18 MiB arena, with a pinned GPU-fence sentinel preserved.
- Concurrent guest-thread IRQL isolation, aggregate interrupt gating, nested
  ISR restoration and thread-exit cleanup.
- Texture reuse after 64 full-cache evictions, including readback of modified
  guest pixels using a headless D3D11 WARP device.
- Audio DSP-memory and recursive audio-guard checks.

From the `scghost` directory, after building Release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run_render_dispatch_native.ps1 -CheckRenderingDefaults
```

The toolkit's focused IRQL and texture-cache regressions can be run separately:

```powershell
cmake -S ..\xboxrecomp\tests\kernel_irql_abi -B ..\xboxrecomp\build-xr\kernel-irql-abi -A x64
cmake --build ..\xboxrecomp\build-xr\kernel-irql-abi --config Release --target kernel_irql_abi_test
ctest --test-dir ..\xboxrecomp\build-xr\kernel-irql-abi -C Release --output-on-failure

cmake -S ..\xboxrecomp\tests\nv2a_texture_cache -B ..\xboxrecomp\build-xr\nv2a-texture-cache -A x64
cmake --build ..\xboxrecomp\build-xr\nv2a-texture-cache --config Release --target nv2a_texture_cache_test
ctest --test-dir ..\xboxrecomp\build-xr\nv2a-texture-cache -C Release --output-on-failure
```

Gameplay verification exercised repeated level changes, mission reload and
return to the menu. The repeat run no longer stalled or progressively lost
FPS, and renderer counters confirmed texture reuse at the 1024-entry limit.
These results do not establish a universal FPS target or complete gameplay
compatibility. Compare the same scene, build configuration and settings when
checking for performance regressions; a responsive window or rendered loading
screen alone does not prove that a transition completed.

## Troubleshooting

### Mission-Exit Stalls

Without reclamation, reloads can exhaust the 64 MB contiguous arena;
subsequent texture initialization can corrupt the GPU-completion word and
stall mission exit. Keep Ghost's `RECOMP_HEAP_RECLAIM=1` default enabled.
An explicit `RECOMP_HEAP_RECLAIM=0` disables reclamation for diagnosis, not
normal play.

The toolkit must also retain thread-local guest IRQL with aggregate interrupt
gating. Sharing saved IRQL across concurrently executing guest threads lets
XACT skip its critical section and corrupt pending-audio lists during teardown.
Reclamation alone does not fix that separate stall; both runtime fixes are
required.

### Progressive Slowdown After Mission Changes

Retain the toolkit's texture-cache index invalidation after insertion. Once
the cache reaches 1024 entries, eviction plus insertion keeps its size
unchanged; a stale source index then causes repeated native texture creation
and progressive slowdown. The WARP regression covers this boundary and
changed-pixel readback without changing cache budgets or bypassing validation.
Increasing the cache limit or flushing all textures is not a substitute for
correct lookup-index invalidation.

### Build and Asset Errors

| Error | Check |
| --- | --- |
| Missing or unpatched generated sources during CMake configuration | Run `regen.sh`; it applies the source patchset before publishing. |
| Unresolved entry-point or dispatch symbols | Ensure CMake includes `src\game\recomp\gen` and reconfigure after changing generated files. |
| `sub_00320B70` redefinition with different basic types | The patched `recomp_funcs.h` must include `recomp_overrides.h` before its closing include guard. |
| Missing generated chunk or object file | Wait for regeneration to finish, then reconfigure and rebuild. Do not regenerate during compilation. |
| Patch does not apply | Check the baseline and whether it is already patched; avoid forced or partial application. |
| Executable cannot load the XBE or assets | Check `XBOXRECOMP_DIR\game_files` and the configured paths printed in the startup log. |

Do not replace failed guest calls or unsupported GPU operations with silent
success merely to advance execution. Build errors, runtime compatibility,
visual correctness and performance need separate verification.

## Build Synchronization

The original port's targeted Debug movie-decoder optimization is also applied
here. CMake locates the six profiled decoder definitions in the generated
sources, so regeneration can move them between chunks without losing `/O2`.
Runtime checks are disabled for those optimized chunks; other Debug sources
keep their normal settings. Release already optimizes all generated sources.

This project retains its generated-patch workflow, native GPU fences and
vblank delivery, plus the newer rendering, audio-guard and window fixes.
Do not replace its startup code or runtime wholesale with an older checkout:
the older fence-mirroring path is not an equivalent synchronization mode.

## Acknowledgments

Special thanks to honored contributor
[@vladislavdonchev](https://github.com/vladislavdonchev) for pushing
StarCraft: Ghost compatibility forward.

## Runtime Documentation

- [XboxRecomp getting started](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/docs/GETTING_STARTED.md).
- [Native NV2A to D3D11 translation](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/docs/runtime/nv2a-d3d11-backend.md).
- [Input integration](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/src/input/README.md).
- [Audio implementation](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/src/apu/README.md).
