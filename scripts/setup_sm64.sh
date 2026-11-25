#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROM_PATH="${1:?usage: setup_sm64.sh /absolute/path/to/baserom.us.z64}"
SM64_DIR="$PROJECT_DIR/.cache/sm64ex"
PIN="d7ca2c04364a6dd0dac58b47151e04e26887e6f0"
if command -v sha1sum >/dev/null; then
  ROM_SHA="$(sha1sum "$ROM_PATH" | cut -d ' ' -f1)"
else
  ROM_SHA="$(shasum -a 1 "$ROM_PATH" | cut -d ' ' -f1)"
fi
if [[ "$ROM_SHA" != "9bef1128717f958171a4afac3ed78ee2bb4e86ce" ]]; then
  echo "ROM validation failed: expected unmodified US .z64 (SHA-1 9bef1128717f958171a4afac3ed78ee2bb4e86ce)." >&2
  exit 2
fi

if [[ ! -d "$SM64_DIR/.git" ]]; then
  git clone https://github.com/sm64pc/sm64ex.git "$SM64_DIR"
fi
if [[ "$(git -C "$SM64_DIR" rev-parse HEAD)" != "$PIN" ]]; then
  git -C "$SM64_DIR" fetch origin "$PIN"
  git -C "$SM64_DIR" checkout --detach "$PIN"
fi
if git -C "$SM64_DIR" apply --check "$PROJECT_DIR/patches/sm64ex-fly64.patch" 2>/dev/null; then
  git -C "$SM64_DIR" apply "$PROJECT_DIR/patches/sm64ex-fly64.patch"
elif git -C "$SM64_DIR" apply --reverse --check "$PROJECT_DIR/patches/sm64ex-fly64.patch" 2>/dev/null; then
  echo "Fly64 patch is already applied."
else
  echo "The Fly64 SM64 patch does not apply cleanly at pinned commit $PIN" >&2
  exit 1
fi

cp "$ROM_PATH" "$SM64_DIR/baserom.us.z64"

if [[ "$(uname -s)" == Linux ]]; then
  missing=()
  for header in /usr/include/SDL2/SDL.h /usr/include/GL/glew.h; do
    [[ -f "$header" ]] || missing+=("$header")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing build headers: ${missing[*]}" >&2
    echo "On Debian/Ubuntu run: sudo apt install build-essential pkg-config libsdl2-dev libglew-dev" >&2
    exit 1
  fi
  # GCC >= 15 defaults to C23, where this 2021 code's own bool/true/false
  # definitions are errors, so pin gnu11. sm64ex passes CC=$(CC) unquoted to
  # sub-makes, so the flag must live in a wrapper rather than inside CC.
  CC_WRAPPER="$PROJECT_DIR/.cache/bin/gcc-gnu11"
  mkdir -p "$(dirname "$CC_WRAPPER")"
  printf '#!/bin/sh\nexec gcc -std=gnu11 "$@"\n' > "$CC_WRAPPER"
  chmod +x "$CC_WRAPPER"
  cd "$SM64_DIR"
  # Same serial first build as macOS.
  make -j1 VERSION=us CC="$CC_WRAPPER" CXX=g++ CPP="cpp -P" \
    BETTERCAMERA=1 NODRAWINGDISTANCE=1 EXT_OPTIONS_MENU=1
  exit 0
fi

missing=()
for formula in make sdl2 glew pkg-config mingw-w64; do
  brew list "$formula" >/dev/null 2>&1 || missing+=("$formula")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install "${missing[@]}"
fi

cd "$SM64_DIR"
export PATH="$(brew --prefix pkgconf)/bin:$PATH"
# This 2021 nightly's generated-asset rules are not parallel-safe on modern
# GNU Make; a serial first build is deterministic and incremental rebuilds are fast.
gmake -j1 VERSION=us \
  CC=clang CXX=clang++ CPP="clang -E -P -x c" \
  BETTERCAMERA=1 NODRAWINGDISTANCE=1 EXT_OPTIONS_MENU=1
