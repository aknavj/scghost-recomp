# StarCraft: Ghost (Release) - Xbox Recomp

Native Windows port of the Xbox StarCraft: Ghost executable using
[XboxRecomp](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/README.md).
Original x86 game code is translated to C and linked with the XboxRecomp runtime.

## Port Progress

| Feature | Status | Notes |
| --- | --- | --- |
| Video playback | Working | Intro videos play through to the menu. |
| Menu scene | Verified | Character, room and logo effects render correctly. |
| Controller input | Verified | Physical controller and menu navigation work. |
| Loading screen | Tested | Briefings and mission loads complete. |
| Gameplay | Working | Tested missions, reloads and level changes work. |
| Mission transitions | Tested | Repeated level changes, reload and return to the menu pass. |
| Audio | Working | Intro and gameplay sound work; XACT teardown is fixed. |
| Rendering | Working | Native GPU rendering works; fence corruption and cache churn are fixed. |
| Performance | Tested | No progressive FPS loss across repeated mission changes. |

Most reported issues are resolved. Full mission coverage, additional save/load
paths and audio/visual fidelity still need validation. FPS remains scene-dependent.

## Requirements

- Windows x64.
- Visual Studio 2022 with **Desktop development with C++** and a Windows SDK.
- CMake 3.20 or newer.
- Git for Windows with Git Bash.
- Python 3.10 or newer with the `py` launcher and XboxRecomp's Python dependencies,
  including `capstone`.
- [XboxRecomp](https://github.com/aknavj/xboxrecomp/tree/modded-software-aknavj-rebased)
  on **`modded-software-aknavj-rebased`**, including the current IRQL, reclamation
  and texture-cache fixes. The default branch is not supported.
- Your own legally obtained game executable and extracted data. Game files are
  not included.

## Setup

Keep `scghost` and `xboxrecomp` beside each other. From their parent directory:

```powershell
git clone --branch modded-software-aknavj-rebased https://github.com/aknavj/xboxrecomp.git xboxrecomp
py -3 -m pip install capstone
```

For an existing toolkit clone, run from `scghost`. Preserve local changes before
switching branches:

```powershell
git -C ..\xboxrecomp fetch origin
git -C ..\xboxrecomp switch modded-software-aknavj-rebased
```

Place game files as follows:

| Purpose | Path relative to the parent directory |
| --- | --- |
| Recompilation input | `scghost\game\StarCraft Ghost\Ghost.xbe` |
| Runtime executable | `xboxrecomp\game_files\Ghost.xbe` |
| Extracted game data | `xboxrecomp\game_files\` |

Use the same XBE in both locations and preserve the extracted directory structure.
[CMakeLists.txt](CMakeLists.txt) configures runtime paths through `XBOXRECOMP_DIR`,
which defaults to `..\xboxrecomp`.

## Build and Run

Run all remaining commands from `scghost`.

### Generate

In **Git Bash**:

```bash
bash regen.sh
```

- Regeneration applies the generated-code patches automatically.
- Use `bash regen.sh --disasm` to rebuild disassembly.
- Generated sources: `src\game\recomp\gen` (ignored by Git).
- Logs: `build\xr`. Previous generated trees: `build\regen-backups`.
- Failed generation or patching leaves the existing sources intact.
- Do not regenerate while compiling. Remove a stale `build\xr\regen.lock`
  only after confirming no regeneration process is active.

### Compile and Launch

In **PowerShell**:

```powershell
cmake -S . -B build-xr -G "Visual Studio 17 2022" -A x64
cmake --build build-xr --config Release --parallel 2
.\build-xr\Release\Ghost.exe
```

Use a physical controller. Keyboard input is disabled by default.
Logs are written beside the executable as `Ghost-run.log` and `Ghost-errors.log`.
Preserve both before another diagnostic run.

### Generated-Code Patches

For manual maintenance, in **Git Bash**:

```bash
bash patch.sh --validate  # Check patch files without generated sources
bash patch.sh --check     # Check baseline applicability
bash patch.sh             # Apply to a matching baseline
```

[patch.sh](patch.sh) applies the ordered [series](patches/generated/series) as
one transaction and detects an already-applied patchset. The baseline must match
the XBE, toolkit output and `--all --split 250` generation settings.
Do not force mismatched patches or normalize their line endings. Add new patch
members to `series`; patches outside `patches\generated` are not applied automatically.

## Runtime Defaults

Configured by [main.c](src/main.c) before runtime initialization:

| Setting | Default | Purpose |
| --- | --- | --- |
| `RECOMP_HEAP_RECLAIM` | `1` | Reuse freed heap and contiguous memory. |
| `RECOMP_TITLE_KEVENTS` | `1` | Support guest-created D3D events. |
| `RECOMP_APU_DIAG` | `0` | Disable verbose audio diagnostics. |
| `RECOMP_FB_SCALE` | `1` | Native framebuffer scale. |
| `RECOMP_FB_D3D11` | `0` | Default framebuffer presentation path. |
| `RECOMP_KEYBOARD` | `0` | Disable keyboard input. |
| `RECOMP_WATCHDOG_SECS` | Forced to `0` | Disable timed process termination. |

Explicit overrides are preserved except for the timed watchdog, which is always
disabled. Native GPU fences and vblank delivery remain enabled.

For non-terminating stall diagnostics:

```powershell
$env:RECOMP_STALL_DUMP = '1'
.\build-xr\Release\Ghost.exe
```

If a stall occurs, keep the process open for capture and preserve both logs.

## Validation

The Release build and repeated mission-change/reload sequence passed without
stalls or progressive FPS loss. Compare the same scene and settings when
measuring performance; a loading screen alone does not prove a completed load.

Passed regression coverage:

- Startup defaults, overrides, guest events and disabled timed watchdog.
- 900 MiB of contiguous allocation churn in an approximately 18 MiB arena,
  preserving a pinned GPU-fence sentinel.
- Thread-local IRQL, aggregate interrupt gating, nested ISR and thread-exit cleanup.
- 64 full-cache texture evictions and changed-pixel readback on D3D11 WARP.
- DSP-memory and recursive audio-guard checks.

Toolkit fixtures: `tests\kernel_irql_abi`, `tests\nv2a_texture_cache` and
`tests\apu_dsp_memory`. These checks do not establish full game compatibility.

## Troubleshooting

| Problem | Action |
| --- | --- |
| Missing generated sources or dispatch symbols | Run `bash regen.sh`, then reconfigure CMake. |
| Missing generated object | Finish regeneration before compiling; do not run both together. |
| Patch mismatch | Check the XBE, toolkit and generation settings. Do not force application. |
| `sub_00320B70` redefinition | Ensure patched `recomp_funcs.h` includes `recomp_overrides.h` before its closing guard. |
| Missing XBE or assets | Check `XBOXRECOMP_DIR\game_files` and the startup log. The old load-error dialog may mention `default.xbe`; the configured file is `Ghost.xbe`. |
| Mission-exit stall | Keep reclamation enabled and use the toolkit's thread-local IRQL with aggregate interrupt gating. |
| Progressive slowdown | Use the texture-cache index fix: insertion must invalidate the index even when eviction keeps the cache at 1024 entries. |

Do not bypass failed guest calls, fabricate fence completion or replace native
fences with the older mirroring path. Increasing cache limits or flushing textures
does not fix a stale lookup index.

## Acknowledgments

See [Contributors](Contributors.md) for contributor credits.

## Documentation

- [Getting started](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/docs/GETTING_STARTED.md).
- [Native NV2A / D3D11 backend](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/docs/runtime/nv2a-d3d11-backend.md).
- [Input](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/src/input/README.md).
- [Audio](https://github.com/aknavj/xboxrecomp/blob/modded-software-aknavj-rebased/src/apu/README.md).
