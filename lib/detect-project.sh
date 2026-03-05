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
  if [ ${#bins[@]} -eq 0 ]; then
    echo '[]'
  else
    printf '%s\n' "${bins[@]}" | jq -R . | jq -s .
  fi
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

# Detect available LOCI-compatible cross-compilers
detect_cross_compilers() {
  local compilers=()
  command -v aarch64-linux-gnu-g++ >/dev/null 2>&1 && compilers+=("aarch64")
  command -v arm-none-eabi-g++ >/dev/null 2>&1 && compilers+=("cortexm")
  command -v tricore-elf-g++ >/dev/null 2>&1 && compilers+=("tricore")
  if [ ${#compilers[@]} -eq 0 ]; then
    echo '[]'
  else
    printf '%s\n' "${compilers[@]}" | jq -R . | jq -s .
  fi
}

# Map detected architecture to LOCI target (aarch64, cortexm, tricore) or null
resolve_loci_target() {
  local arch="$1"
  local cross_compilers="$2"
  local lower_arch
  lower_arch=$(echo "$arch" | tr '[:upper:]' '[:lower:]')
  case "$lower_arch" in
    aarch64|arm64)
      echo "aarch64" ;;
    arm|armv7*|cortex-m*|thumb)
      echo "cortexm" ;;
    tricore|tc3*|tc39*)
      echo "tricore" ;;
    *)
      # Host arch is not a LOCI target — check if any cross-compiler is available
      # Pick the first available cross-compiler as default
      local first
      first=$(echo "$cross_compilers" | jq -r '.[0] // empty' 2>/dev/null)
      if [ -n "$first" ]; then
        echo "$first"
      else
        echo "null"
      fi
      ;;
  esac
}

COMPILER=$(detect_compiler)
BUILD_SYSTEM=$(detect_build_system)
SOURCES=$(find_sources)
BINARIES=$(find_binaries)
ASM_FILES=$(find_asm_files)
ARCH=$(detect_architecture)
CROSS_COMPILERS=$(detect_cross_compilers)
LOCI_TARGET=$(resolve_loci_target "$ARCH" "$CROSS_COMPILERS")

# Determine LOCI compatibility
if [ "$LOCI_TARGET" != "null" ]; then
  LOCI_COMPATIBLE="true"
else
  LOCI_COMPATIBLE="false"
fi

jq -n \
  --arg compiler "$COMPILER" \
  --arg build_system "$BUILD_SYSTEM" \
  --arg project_type "cpp" \
  --arg architecture "$ARCH" \
  --argjson source_files "$SOURCES" \
  --argjson binaries "$BINARIES" \
  --argjson asm_files "$ASM_FILES" \
  --argjson cross_compilers "$CROSS_COMPILERS" \
  --argjson loci_compatible "$LOCI_COMPATIBLE" \
  --arg loci_target "$LOCI_TARGET" \
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
    cross_compilers: $cross_compilers,
    loci_compatible: $loci_compatible,
    loci_target: (if $loci_target == "null" then null else $loci_target end),
    detected_at: $detected_at
  }'
