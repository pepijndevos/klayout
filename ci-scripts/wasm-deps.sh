#!/usr/bin/env bash
# Build the static WebAssembly libraries the Python module links in and Emscripten does
# not provide as a port. libpng and zlib come from the Emscripten ports (see setup.py),
# this builds expat, which the LEF/DEF readers use.
#
# Requires an activated emsdk (emcc on PATH) with the Emscripten version of the Pyodide
# target.
#
# Usage: ci-scripts/build-wasm-deps.sh <prefix> [work-dir]
set -euo pipefail

EXPAT_VERSION=2.10.0

PREFIX="$(mkdir -p "${1:?usage: $0 <prefix> [work-dir]}" && cd "$1" && pwd)"
WORK="${2:-$(mktemp -d)}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

command -v emcc >/dev/null || { echo "emcc not found: activate emsdk first" >&2; exit 1; }

# -fPIC because everything ends up inside a shared (side) module.
CFLAGS_WASM="-O2 -fPIC"

if [ -f "$PREFIX/lib/libexpat.a" ]; then
  echo "==> expat $EXPAT_VERSION already built in $PREFIX"
  exit 0
fi

echo "==> expat $EXPAT_VERSION"
if [ ! -f "$WORK/expat-$EXPAT_VERSION.tar.gz" ]; then
  curl -fsSL -o "$WORK/expat-$EXPAT_VERSION.tar.gz" \
    "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-$EXPAT_VERSION.tar.gz"
fi
rm -rf "$WORK/expat-$EXPAT_VERSION" "$WORK/expat-build"
tar xzf "$WORK/expat-$EXPAT_VERSION.tar.gz" -C "$WORK"

# the release tarball has the CMake project at the top level, the git layout has it in expat/
EXPAT_SRC="$WORK/expat-$EXPAT_VERSION"
[ -d "$EXPAT_SRC/expat" ] && EXPAT_SRC="$EXPAT_SRC/expat"

mkdir -p "$WORK/expat-build"
cd "$WORK/expat-build"
emcmake cmake "$EXPAT_SRC" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$CFLAGS_WASM" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DEXPAT_SHARED_LIBS=OFF \
  -DEXPAT_BUILD_TOOLS=OFF \
  -DEXPAT_BUILD_EXAMPLES=OFF \
  -DEXPAT_BUILD_TESTS=OFF \
  -DEXPAT_BUILD_DOCS=OFF
emmake make -j "$JOBS" install

echo "==> expat $EXPAT_VERSION installed into $PREFIX"
