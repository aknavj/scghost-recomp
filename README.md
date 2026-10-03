# StarCraft: Ghost (Release) - Xbox Recomp

Static recompilation of the Xbox StarCraft: Ghost executable using
[XboxRecomp](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/README.md).

The project translates the original x86 game code into C and links it with
the XboxRecomp runtime to produce a native Windows executable. It is a
work-in-progress port, not a complete or verified replacement for the original
Xbox runtime. Successful compilation does not establish gameplay compatibility
or playable performance.

## Port Progress

Reported development-workspace results; not yet reverified in this checkout.

| Feature | Status | Notes |
| --- | --- | --- |
| Video playback | Verified | Visible, changing guest-decoded video; progression past splash confirmed. |
| Menu scene | Verified | Upright character, room and logo effects visually confirmed. |
| Controller input | Verified | Physical-controller input confirmed; full menu navigation remains unverified. |
| Loading screen | Partial | Mission briefing reached; loading-background texture repair remains unverified. |
| Gameplay | Partial | User-confirmed execution; later exits on unsupported texture shader program `0x2`. |
| Audio | Partial | Intro-movie sound confirmed; sustained gameplay audio and DSP effects unverified. |
| Rendering | Partial | Native hardware rendering works; shader/state compatibility gaps remain. |
| Performance | Needs work | Debug menu measured roughly 5.4-5.8 FPS; repaired optimized build still needs measurement. |

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
      generated.patch
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

Analysis and regeneration logs are written under `build\xr`. Generated C
sources and headers are written to `src\game\recomp\gen` and are ignored by Git.

Existing disassembly is reused. To rebuild it:

```bash
bash regen.sh --disasm
```

If regeneration fails, do not build the partially regenerated output. Check
`build\xr\disasm.log` or `build\xr\recomp.log`, resolve the error, and rerun
regeneration.

## Apply the Generated-Code Patch

After generating the unpatched baseline, run in **Git Bash**:

```bash
bash patch.sh --check
bash patch.sh
```

[patch.sh](patch.sh) checks that [generated.patch](patches/generated.patch)
applies before changing files. `--check` performs validation only. The script
can be called from another directory because it resolves paths relative to
its own location.

The patch includes code repairs, preserved functions and a change from 18
generated code chunks to 70. Its large size reflects that rechunking as well
as the code changes. It must match the generated baseline; it is not a
general-purpose patch for arbitrary XBE versions or toolkit output.

Apply it only once. If validation fails, check whether the patch is already
applied or the baseline differs. Do not force partial application.

Before regenerating an already patched tree, reverse the patch from the
project root:

```bash
git apply --reverse --check patches/generated.patch
git apply --reverse --whitespace=nowarn patches/generated.patch
bash regen.sh
bash patch.sh
```

Reversal also removes patch-added files that regeneration might otherwise
leave behind. If the reverse check fails, preserve any local edits and resolve
the mismatch before regenerating.

## Configure and Build

Run from the `scghost` directory in **PowerShell**, after generation and
patching:

```powershell
cmake -S . -B build-xr -G "Visual Studio 17 2022" -A x64
cmake --build build-xr --config Release --parallel 2
```

CMake builds the XboxRecomp libraries and the `Ghost` executable. Generated
source files are large, so compilation can take considerable time.

For subsequent builds:

```powershell
cmake --build build-xr --config Release --parallel 2
```

If regeneration or patching changes the chunk list, explicitly reconfigure
before building to refresh the Visual Studio project:

```powershell
cmake -S . -B build-xr
cmake --build build-xr --config Release --parallel 2
```

`XBOXRECOMP_DIR` is a CMake cache path and defaults to the sibling toolkit.
Changing it does not change the sibling path used by `regen.sh`; keep both
configured consistently if you move the toolkit.

## Run and Diagnose

Start the Release executable from **PowerShell**:

```powershell
& .\build-xr\Release\Ghost.exe
```

Standard output and error are redirected to `Ghost-run.log` and
`Ghost-errors.log` beside the executable. Startup initializes guest memory,
kernel services, input and the NV2A command-stream path.

The startup code supplies diagnostic audio defaults, including AC97 readiness
and DSP acknowledgement. These are bring-up aids, not complete DSP emulation.
Existing environment settings generally take precedence over those defaults.

For framebuffer captures:

```powershell
New-Item -ItemType Directory -Force C:\captures | Out-Null
$env:RECOMP_FB_CAPTURE = 'C:\captures\framebuffer.bmp'
& .\build-xr\Release\Ghost.exe
```

Press **F12** in the framebuffer window to capture its displayed image.

## Troubleshooting

| Error | Check |
| --- | --- |
| Missing generated sources during CMake configuration | Run `regen.sh`, then apply the patch before configuring. |
| Unresolved entry-point or dispatch symbols | Ensure CMake includes `src\game\recomp\gen` and reconfigure after changing generated files. |
| `sub_00320B70` redefinition with different basic types | The patched `recomp_funcs.h` must include `recomp_overrides.h` before its closing include guard. |
| Missing generated chunk or object file | Wait for regeneration to finish, then reconfigure and rebuild. Do not regenerate during compilation. |
| Patch does not apply | Check the baseline and whether it is already patched; avoid forced or partial application. |
| Executable cannot load the XBE or assets | Check `XBOXRECOMP_DIR\game_files` and the configured paths printed in the startup log. |

Do not replace failed guest calls or unsupported GPU operations with silent
success merely to advance execution. Build errors, runtime compatibility,
visual correctness and performance need separate verification.

## Runtime Documentation

- [XboxRecomp getting started](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/docs/GETTING_STARTED.md).
- [Native NV2A to D3D11 translation](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/docs/runtime/nv2a-d3d11-backend.md).
- [Input integration](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/src/input/README.md).
- [Audio implementation](https://github.com/aknavj/xboxrecomp/blob/impl-scghost/src/apu/README.md).
