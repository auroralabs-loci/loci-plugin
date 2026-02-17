#!/bin/bash
# Detect C++ project context: compiler, build system, binaries, ASM files.
# Outputs JSON for session initialization.

set -euo pipefail

CWD="${1:-.}"

# Detect C++ compiler
detect_compiler() {
  if command -v g++ >/dev/null 2>&1; then
    echo "g++"
  elif command -v clang++ >/dev/null 2>&1; then
    echo "clang++"
  else
    echo "unknown"
  fi
}

# Detect build system
detect_build_system() {
  [ -f "$CWD/CMakeLists.txt" ] && echo "cmake" && return
  [ -f "$CWD/Makefile" ] || [ -f "$CWD/makefile" ] && echo "make" && return
  [ -f "$CWD/meson.build" ] && echo "meson" && return
  [ -f "$CWD/BUILD" ] || [ -f "$CWD/WORKSPACE" ] && echo "bazel" && return
  [ -f "$CWD/conanfile.txt" ] || [ -f "$CWD/conanfile.py" ] && echo "conan" && return
  [ -f "$CWD/vcpkg.json" ] && echo "vcpkg" && return
  echo "direct"
}

# Find C++ source files
find_sources() {
  find "$CWD" -maxdepth 2 \( -name "*.cpp" -o -name "*.cxx" -o -name "*.cc" -o -name "*.c" -o -name "*.h" -o -name "*.hpp" \) 2>/dev/null | head -20 | jq -R . | jq -s .
}

# Find compiled binaries and object files
find_binaries() {
  local bins=()
  for f in "$CWD"/*; do
    if [ -f "$f" ] && [ -x "$f" ] && file "$f" 2>/dev/null | grep -qiE '(ELF|Mach-O|executable)'; then
      bins+=("$(basename "$f")")
    fi
  done
  printf '%s\n' "${bins[@]}" 2>/dev/null | jq -R . | jq -s . || echo '[]'
}

# Find assembly files
find_asm_files() {
  find "$CWD" -maxdepth 2 \( -name "*.asm" -o -name "*.s" -o -name "*.S" \) 2>/dev/null | head -20 | jq -R . | jq -s .
}

# Detect architecture from existing binaries
detect_architecture() {
  for f in "$CWD"/*; do
    if [ -f "$f" ] && [ -x "$f" ] && file "$f" 2>/dev/null | grep -qiE '(ELF|Mach-O)'; then
      file "$f" | grep -oiE '(x86.64|arm64|aarch64|i386|x86_64)' | head -1
      return
    fi
  done
  uname -m
}

COMPILER=$(detect_compiler)
BUILD_SYSTEM=$(detect_build_system)
SOURCES=$(find_sources)
BINARIES=$(find_binaries)
ASM_FILES=$(find_asm_files)
ARCH=$(detect_architecture)

jq -n \
  --arg compiler "$COMPILER" \
  --arg build_system "$BUILD_SYSTEM" \
  --arg project_type "cpp" \
  --arg architecture "$ARCH" \
  --argjson source_files "$SOURCES" \
  --argjson binaries "$BINARIES" \
  --argjson asm_files "$ASM_FILES" \
  --arg detected_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{
    language_stack: ["cpp"],
    compiler: $compiler,
    build_system: $build_system,
    project_type: $project_type,
    architecture: $architecture,
    source_files: $source_files,
    binaries: $binaries,
    asm_files: $asm_files,
    detected_at: $detected_at
  }'
