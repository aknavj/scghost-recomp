# StarCraft: Ghost (Release) - Xbox Recomp

Static recompilation of the Xbox StarCraft: Ghost executable using
[XboxRecomp](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/README.md).

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
| Loading screen | Partial | Mission briefing reached; background texture unverified. |
| Gameplay | Partial | Gameplay runs, but renderer failures still cause exits. |
| Audio | Partial | Intro and gameplay sound work; occasional crackles and incomplete DSP effects remain. |
| Rendering | Partial | Hardware rendering works; texture and shader support remains incomplete. |
| Performance | Needs work | Debug menu: about 10-15 FPS; sustained optimized performance unverified. |

## Requirements

- Windows x64.
- Visual Studio 2022 with **Desktop development with C++** and a Windows SDK.
- CMake 3.20 or newer.
- Git for Windows, including Git Bash.
- Python 3.10 or newer with the Windows `py` launcher.
- The Python dependencies required by XboxRecomp, including `capstone`.
- [aknavj/xboxrecomp](https://github.com/aknavj/xboxrecomp/tree/impl-scghost)
  checked out on the **`impl-scghost` branch**.
- Your own legally obtained game executable and extracted data files.

**The `impl-scghost` toolkit branch is required for correct behavior.** It
contains the runtime and recompilation changes needed by this port; the default
branch is not a supported substitute.

To clone the required branch beside this project, run from the parent directory:

```powershell
git clone --branch impl-scghost https://github.com/aknavj/xboxrecomp.git xboxrecomp
```

For an existing clone of that fork, preserve any local changes before switching:

```powershell
git -C ..\xboxrecomp fetch origin
git -C ..\xboxrecomp switch impl-scghost
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

## Troubleshooting

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
Compare the same configuration and scene when measuring performance:

```powershell
cmake -S . -B build-xr
cmake --build build-xr --config Release --target Ghost --parallel 2
.\build-xr\Release\Ghost.exe
```

## Runtime Documentation

- [XboxRecomp getting started](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/docs/GETTING_STARTED.md).
- [Native NV2A to D3D11 translation](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/docs/runtime/nv2a-d3d11-backend.md).
- [Input integration](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/src/input/README.md).
- [Audio implementation](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/src/apu/README.md).
