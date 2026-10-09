cmake_minimum_required(VERSION 3.20)

# ============================================================================
# StarCraft Ghost (Release) - Static Recompilation
#
# Copy this template to your game project root and customize:
#   1. Change the project name below
#   2. Set XBOXRECOMP_DIR to where you cloned xboxrecomp
#   3. Adjust source file lists as you add game-specific code
#   4. Add any game-specific compile definitions or link libraries
# ============================================================================

project(Ghost VERSION 0.1.0.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Common definitions
add_compile_definitions(
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

# ── xboxrecomp toolkit ──────────────────────────────────────────
#
# Option A: xboxrecomp as a subdirectory (simplest)
#   Place xboxrecomp/ next to your game project and use a relative path.
#
# Option B: find_package (if you install xboxrecomp system-wide)
#   find_package(xboxrecomp REQUIRED)
#
# Adjust this path to point to your xboxrecomp clone:
set(XBOXRECOMP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../xboxrecomp" CACHE PATH
    "Path to the xboxrecomp toolkit root directory")

file(TO_CMAKE_PATH "${XBOXRECOMP_DIR}/game_files" GHOST_GAME_FILES_DIR)
configure_file(src/game_paths.h.in game_paths.h @ONLY)

# Add xboxrecomp as a subdirectory -- this builds all 6 runtime libraries
# and provides the 'xboxrecomp' umbrella target to link against.
add_subdirectory(${XBOXRECOMP_DIR} ${CMAKE_BINARY_DIR}/xboxrecomp)

# ── Recompiled game executable ──────────────────────────────────

# Collect generated recompiled code.
# The recomp pipeline outputs files into src/game/recomp/gen/.
# With --split 250, you get recomp_0000.c, recomp_0001.c, etc.
# CONFIGURE_DEPENDS so re-running the recompiler picks up added/removed files
# without a manual re-configure. A plain GLOB is evaluated once at configure
# time, so a newly generated file (an extra chunk, recomp_stubs_unresolved.c)
# is silently left out of the build and shows up as unresolved externals.
set(RECOMP_GEN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/game/recomp/gen")
file(GLOB RECOMP_GEN_SOURCES CONFIGURE_DEPENDS "${RECOMP_GEN_DIR}/*.c")
if(NOT RECOMP_GEN_SOURCES OR
   NOT EXISTS "${RECOMP_GEN_DIR}/recomp_dispatch.c" OR
   NOT EXISTS "${RECOMP_GEN_DIR}/recomp_funcs.h" OR
   NOT EXISTS "${RECOMP_GEN_DIR}/recomp_types.h" OR
   NOT EXISTS "${RECOMP_GEN_DIR}/recomp_overrides.h" OR
   NOT EXISTS "${RECOMP_GEN_DIR}/recomp_preserved.c")
    message(FATAL_ERROR
        "Patched recompiled game sources are missing or incomplete. "
        "Run bash regen.sh from the scghost directory in Git Bash, then configure again.")
endif()

# Core game sources
set(GAME_SOURCES
    src/main.c
    src/recomp_manual.c
    # Add game-specific sources here, e.g.:
    # src/asset_loader.c
    # src/custom_renderer.c
)

# The recomp pipeline also generates a dispatch header and function declarations.
# These are included by the generated .c files:
#   src/game/recomp/gen/recomp_funcs.h    - recompiled function declarations
#   src/game/recomp/gen/recomp_dispatch.c - function dispatch table
#   src/game/recomp/gen/recomp_types.h    - register model, ICALL macros, MEM helpers

add_executable(${PROJECT_NAME} WIN32
    ${GAME_SOURCES}
    ${RECOMP_GEN_SOURCES}
)

if(WIN32)
    enable_language(RC)
    set(GHOST_ICON_PATH "${CMAKE_CURRENT_SOURCE_DIR}/res/icon.ico")
    configure_file(res/Ghost.rc.in Ghost.rc @ONLY)
    target_sources(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/Ghost.rc")
endif()

# Link against the xboxrecomp umbrella target (all 6 runtime libraries)
target_link_libraries(${PROJECT_NAME} PRIVATE xboxrecomp)

# Include paths for generated recomp headers
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${RECOMP_GEN_DIR}
    ${XBOXRECOMP_DIR}/include
)

# Windows SDK libraries needed at link time
target_link_libraries(${PROJECT_NAME} PRIVATE
    d3d11
    dxgi
    dxguid
    xinput
    winmm
    # Lets the fault handler resolve the host RIP back to the generated
    # function's symbol, i.e. to the guest function that faulted.
    dbghelp
)

# MSVC-specific: large address aware, increase section limit for big generated files
if(MSVC)
    option(GHOST_RELEASE_SYMBOLS "Emit symbols for optimized Release hang diagnostics" ON)
    if(GHOST_RELEASE_SYMBOLS)
        target_compile_options(${PROJECT_NAME} PRIVATE "$<$<CONFIG:Release>:/Zi>")
        target_compile_options(xbox_kernel PRIVATE "$<$<CONFIG:Release>:/Zi>")
        target_link_options(${PROJECT_NAME} PRIVATE
            "$<$<CONFIG:Release>:/DEBUG:FULL>"
            "$<$<CONFIG:Release>:/OPT:REF>"
            "$<$<CONFIG:Release>:/OPT:ICF>")
    endif()
    target_link_options(${PROJECT_NAME} PRIVATE
        /LARGEADDRESSAWARE
    )
    # The generated code files can be very large. Increase object file section limit.
    target_compile_options(${PROJECT_NAME} PRIVATE /bigobj)
    foreach(recomp_source IN ITEMS ${RECOMP_GEN_SOURCES})
        file(STRINGS "${recomp_source}" hot_movie_decoder LIMIT_COUNT 1
            REGEX "^void sub_002(30170|312D0|31C10|330A0|36090|37410)\\(void\\)")
        if(hot_movie_decoder)
            set_property(SOURCE "${recomp_source}" APPEND PROPERTY
                COMPILE_OPTIONS "$<$<CONFIG:Debug>:/O2>")
            set_property(SOURCE "${recomp_source}" APPEND PROPERTY
                VS_SETTINGS "BasicRuntimeChecks=Default")
        endif()
    endforeach()
endif()

# ── Game-specific additions ─────────────────────────────────────
#
# Add any game-specific libraries, loaders, or custom renderers below.
# Examples:
#
# # Custom texture loader for your game's format
# target_sources(${PROJECT_NAME} PRIVATE src/texture_loader.c)
#
# # If your game uses RenderWare, you may need a RW bridge layer
# target_sources(${PROJECT_NAME} PRIVATE src/rw_bridge.c)
#
# # Additional compile definitions for debugging
# target_compile_definitions(${PROJECT_NAME} PRIVATE
#     ENABLE_ICALL_TRACE=1
#     VERBOSE_KERNEL_LOG=1
# )
