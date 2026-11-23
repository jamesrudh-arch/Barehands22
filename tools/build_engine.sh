#!/usr/bin/env bash
# Rebuild the Godot 4.7.2 headless-capable editor binary + toolchain in /tmp.
# /tmp is wiped between sessions; this script is the canonical recipe.
# Usage: bash tools/build_engine.sh  (long: ~40-60 min with -j2)
set -x
GODOT_VER=4.7.2-stable
BIN=/tmp/godot-${GODOT_VER}/bin/godot.linuxbsd.editor.x86_64

# 1. python venv with gdtoolkit + scons + numpy
if [ ! -x /tmp/gvenv/bin/scons ]; then
  python3 -m venv /tmp/gvenv
  /tmp/gvenv/bin/pip install -q --upgrade pip
  /tmp/gvenv/bin/pip install -q gdtoolkit==4.* scons numpy
fi

# 2. pkgconf-lite (provides pkg-config for scons deps)
if [ ! -x /tmp/pkgconf/bin/pkg-config ]; then
  cd /tmp
  if [ ! -d pkgconf-pkgconf-3.0.11 ]; then
    curl -sL https://github.com/pkgconf/pkgconf/archive/refs/tags/pkgconf-3.0.11.tar.gz -o pkgconf.tgz
    tar xzf pkgconf.tgz
  fi
  cd pkgconf-pkgconf-3.0.11
  make -f Makefile.lite SYSTEM_LIBDIR=/usr/lib/x86_64-linux-gnu \
    SYSTEM_INCLUDEDIR=/usr/include \
    PKG_DEFAULT_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig -j2 >/dev/null
  mkdir -p /tmp/pkgconf/bin
  cp pkgconf-lite /tmp/pkgconf/bin/pkg-config
fi
export PATH=/tmp/pkgconf/bin:/tmp/gvenv/bin:$PATH

# 3. godot source
if [ ! -x "$BIN" ]; then
  cd /tmp
  if [ ! -d godot-${GODOT_VER} ]; then
    curl -sL https://github.com/godotengine/godot/archive/refs/tags/${GODOT_VER}.tar.gz -o godot.tgz
    tar xzf godot.tgz
  fi
  cd godot-${GODOT_VER}
  scons -j2 platform=linuxbsd target=editor
  echo "SCONS_EXIT=$?"
fi

ls -la /tmp/godot-${GODOT_VER}/bin/ 2>/dev/null
echo "BUILD3_DONE_MARKER"
