#!/usr/bin/env bash
# Builds a static Jasper, which WPS links into ungrib.exe for JPEG2000 GRIB2.
# Jasper isn't packaged in Debian trixie. Installs to $JASPER_PREFIX.

set -euxo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/versions.sh"

JASPER_PREFIX="${JASPER_PREFIX:-/opt/jasper}"
# The source and build directories are embedded in the library, and so in
# ungrib.exe. They are fixed at the paths earlier builds used, so that
# ungrib.exe is the same file.
src="${JASPER_SRC_PARENT:-/opt}/jasper-${JASPER_VERSION}"
build="${JASPER_SRC_PARENT:-/opt}/jasper-build"
download="$(mktemp -d)"
trap 'rm -rf "$download" "$src" "$build"' EXIT

"$here/fetch.sh" \
  "https://github.com/jasper-software/jasper/releases/download/version-${JASPER_VERSION}/jasper-${JASPER_VERSION}.tar.gz" \
  "jasper-${JASPER_VERSION}.tar.gz" "$download"
tar -xzf "$download/jasper-${JASPER_VERSION}.tar.gz" -C "$(dirname "$src")"

# A static library only: WPS links it into ungrib.exe directly
cmake -S "$src" -B "$build" \
  -DCMAKE_INSTALL_PREFIX="$JASPER_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DJAS_ENABLE_SHARED=OFF \
  -DJAS_ENABLE_LIBJPEG=OFF \
  -DJAS_ENABLE_LIBHEIF=OFF \
  -DJAS_ENABLE_OPENGL=OFF \
  -DJAS_ENABLE_DOC=OFF \
  -DJAS_ENABLE_PROGRAMS=OFF
make -C "$build" -j"$(nproc)"
make -C "$build" install
