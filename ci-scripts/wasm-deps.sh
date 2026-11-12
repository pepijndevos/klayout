#!/usr/bin/env bash
# Build the static WebAssembly libraries the Python module links in: expat (LEF/DEF
# readers) and libpng (PNG support in tl). zlib is built for its headers and for
# libpng's configuration only - Pyodide's main module exports zlib (it is linked with
# -sUSE_ZLIB), so the side modules resolve deflate & co. from there at load time.
#
# Emscripten ports cannot be used for libpng: a side module does not get ports linked
# in, and the libpng port library is neither PIC nor built for wasm exceptions.
#
# Requires an activated emsdk (emcc on PATH) with the Emscripten version of the Pyodide
# target.
#
# Usage: ci-scripts/wasm-deps.sh <prefix> [work-dir]
set -euo pipefail

EXPAT_VERSION=2.10.0
# zlib matches the Emscripten port Pyodide's main module links
ZLIB_VERSION=1.3.1
LIBPNG_VERSION=1.6.55

PREFIX="$(mkdir -p "${1:?usage: $0 <prefix> [work-dir]}" && cd "$1" && pwd)"
WORK="${2:-$(mktemp -d)}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

command -v emcc >/dev/null || { echo "emcc not found: activate emsdk first" >&2; exit 1; }

# -fPIC because everything ends up inside a shared (side) module. The exception and
# longjmp flavour must match Pyodide's (and klayout's) - libpng reports errors via
# longjmp.
CFLAGS_WASM="-O2 -fPIC -fwasm-exceptions -sSUPPORT_LONGJMP=wasm"

fetch() {  # fetch <file> <url>
  [ -f "$WORK/$1" ] || curl -fsSL -o "$WORK/$1" "$2"
}

# --- expat

if [ -f "$PREFIX/lib/libexpat.a" ]; then
  echo "==> expat $EXPAT_VERSION already built in $PREFIX"
else
  echo "==> expat $EXPAT_VERSION"
  fetch "expat-$EXPAT_VERSION.tar.gz" \
    "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-$EXPAT_VERSION.tar.gz"
  rm -rf "$WORK/expat-$EXPAT_VERSION" "$WORK/expat-build"
  tar xzf "$WORK/expat-$EXPAT_VERSION.tar.gz" -C "$WORK"

  # the release tarball has the CMake project at the top level, the git layout has it in expat/
  EXPAT_SRC="$WORK/expat-$EXPAT_VERSION"
  [ -d "$EXPAT_SRC/expat" ] && EXPAT_SRC="$EXPAT_SRC/expat"

  mkdir -p "$WORK/expat-build"
  (
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
  )
  echo "==> expat $EXPAT_VERSION installed into $PREFIX"
fi

# --- zlib (headers + libpng configuration; not linked into klayout, see above)

if [ -f "$PREFIX/lib/libz.a" ]; then
  echo "==> zlib $ZLIB_VERSION already built in $PREFIX"
else
  echo "==> zlib $ZLIB_VERSION"
  fetch "zlib-$ZLIB_VERSION.tar.gz" \
    "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz"
  rm -rf "$WORK/zlib-$ZLIB_VERSION"
  tar xzf "$WORK/zlib-$ZLIB_VERSION.tar.gz" -C "$WORK"
  (
    cd "$WORK/zlib-$ZLIB_VERSION"
    CFLAGS="$CFLAGS_WASM" emconfigure ./configure --static --prefix="$PREFIX"
    emmake make -j "$JOBS" libz.a
    emmake make install
  )
  echo "==> zlib $ZLIB_VERSION installed into $PREFIX"
fi

# --- libpng

if [ -f "$PREFIX/lib/libpng.a" ]; then
  echo "==> libpng $LIBPNG_VERSION already built in $PREFIX"
else
  echo "==> libpng $LIBPNG_VERSION"
  fetch "libpng-$LIBPNG_VERSION.tar.gz" \
    "https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VERSION.tar.gz"
  rm -rf "$WORK/libpng-$LIBPNG_VERSION" "$WORK/libpng-build"
  tar xzf "$WORK/libpng-$LIBPNG_VERSION.tar.gz" -C "$WORK"
  mkdir -p "$WORK/libpng-build"
  (
    cd "$WORK/libpng-build"
    emcmake cmake "$WORK/libpng-$LIBPNG_VERSION" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="$CFLAGS_WASM" \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DZLIB_ROOT="$PREFIX" \
      -DZLIB_INCLUDE_DIR="$PREFIX/include" \
      -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
      -DPNG_SHARED=OFF \
      -DPNG_STATIC=ON \
      -DPNG_FRAMEWORK=OFF \
      -DPNG_TESTS=OFF \
      -DPNG_TOOLS=OFF \
      -DPNG_HARDWARE_OPTIMIZATIONS=OFF
    emmake make -j "$JOBS" install
  )
  echo "==> libpng $LIBPNG_VERSION installed into $PREFIX"
fi
