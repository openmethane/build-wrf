#!/usr/bin/env bash
# Builds WRF into $WRF_DIR and WPS into $WPS_DIR, which are also the paths they
# run from: nothing is moved after the build, so the files in the Debian package
# are the files the build produced. Needs Jasper (scripts/build_jasper.sh) at
# $JASPER_PREFIX, and root or sudo, to alias two library paths below.

set -xe

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/versions.sh"

WRF_DIR="${WRF_DIR:-/opt/wrf}"
WPS_DIR="${WPS_DIR:-/opt/wps}"
export JASPERLIB="${JASPERLIB:-${JASPER_PREFIX:-/opt/jasper}/lib}"
export JASPERINC="${JASPERINC:-${JASPER_PREFIX:-/opt/jasper}/include}"

SUDO=""
[ "$(id -u)" = 0 ] || SUDO=sudo
MULTIARCH="$(gcc -print-multiarch)"

# Link to the compiled dependencies
# NOTE: WRF's own configure/Config.pl ignores $LDFLAGS for netCDF linkage -
# it only adds -lnetcdf/-lnetcdff to the final link line when $NETCDF_LDFLAGS
# is set (otherwise sw_usenetcdf/sw_usenetcdff stay empty, since ./configure
# never passes -usenetcdf=/-usenetcdff= to Config.pl). Without this,
# real.exe/wrf.exe fail to link with "undefined reference to nf_*".
export NETCDF_LDFLAGS="$(nf-config --flibs)"
export CC=gcc
export CXX=g++
export FC=gfortran
export FCFLAGS="-m64  -fallow-argument-mismatch"
export F77=gfortran
export FFLAGS="-m64  -fallow-argument-mismatch"
export NETCDF=$(nc-config --prefix)
export NETCDF4=1
export J="-j 8"
export ARCH=$(uname -m)

# WRF's configure always links against unsuffixed -lhdf5/-lhdf5_hl and expects
# to find them via $HDF5_PATH/lib, so alias the actual installed library in
# "/usr/lib/x86_64-linux-gnu/hdf5/serial" as "/lib" and point to its parent.
$SUDO ln -sfn /usr/lib/${MULTIARCH}/hdf5/serial /usr/lib/${MULTIARCH}/hdf5/lib
export HDF5_PATH=/usr/lib/${MULTIARCH}/hdf5

# WPS's own configure only adds -lnetcdff to its link line when it finds a
# static $NETCDF/lib/libnetcdff.a; Debian puts that file under the multiarch
# directory, not the plain lib dir, so alias it in place. Without this,
# metgrid.exe/ungrib.exe fail to link with "undefined reference to nf90_*".
$SUDO ln -sf /usr/lib/${MULTIARCH}/libnetcdff.a /usr/lib/libnetcdff.a

# GCC 14 (shipped in trixie) turns implicit-function-declaration/implicit-int
# from warnings into hard errors by default. WRF/WPS's bundled C sources (the
# Registry tool, io_grib1, io_grib_share, WPS's cio.c) predate that and rely
# on implicit declarations of libc functions, so demote those back to
# warnings wherever we patch in generated build configs below.
GCC14_COMPAT_CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Build WRF
"$here/fetch.sh" \
  "https://github.com/wrf-model/WRF/releases/download/v${WRF_VERSION}/v${WRF_VERSION}.tar.gz" \
  "WRF-v${WRF_VERSION}.tar.gz" "$work"
mkdir -p "$WRF_DIR"
tar -xzf "$work/WRF-v${WRF_VERSION}.tar.gz" -C "$WRF_DIR" --strip-components=1
pushd "$WRF_DIR"

if [[ $ARCH == "aarch64" ]]; then
  echo "11\n1\n" | ./configure  # dmpar + gfortran + aarch64
else
  echo "34\n1\n" | ./configure  # dmpar + gfortran + x86_64
fi

sed -i "s/\(CFLAGS_LOCAL[[:space:]]*=[[:space:]]*-w -O3 -c\)/\1 ${GCC14_COMPAT_CFLAGS}/" configure.wrf
sed -i "s/\(CFLAGS = \$(CC_TOOLS_CFLAGS)\)/\1 ${GCC14_COMPAT_CFLAGS}/" tools/Makefile

./compile em_real
popd

# Build WPS
"$here/fetch.sh" \
  "https://github.com/wrf-model/WPS/archive/v${WPS_VERSION}.tar.gz" \
  "WPS-v${WPS_VERSION}.tar.gz" "$work"
mkdir -p "$WPS_DIR"
tar -xzf "$work/WPS-v${WPS_VERSION}.tar.gz" -C "$WPS_DIR" --strip-components=1
pushd "$WPS_DIR"

# WPS finds the compiled WRF through this
export WRF_DIR

# Add some compiler options for aarch64 (based on x86_64)
cat "$here/configure.aarch64" >> arch/configure.defaults

# option 1 = serial/gfortran/GRIB2. Without GRIB2 support, ungrib.exe refuses
# to decode Grib Edition 2 data (most current GFS/ERA5 sources) with
# NEED_GRIB2_LIBS. $JASPERLIB/$JASPERINC (set above) point
# ./configure at the Jasper build from scripts/build_jasper.sh, so this
# picks up real JPEG2000 + PNG support, matching an unmodified WPS build.
echo "1" | ./configure # serial + gfortran, GRIB2

# See the GCC14_COMPAT_CFLAGS note above - WPS's own cio.c hits the same
# implicit-function-declaration/implicit-int errors, and configure.wps's
# CFLAGS for this arch starts out empty (no "-w" to interact with).
sed -i "s/\(^CFLAGS[[:space:]]*=\)[[:space:]]*$/\1 ${GCC14_COMPAT_CFLAGS}/" configure.wps

# WPS 4.2-4.6 reads an uninitialised local (is_subgrid_var) when building
# metgrid's output field list; under gfortran 14 every field is discarded and
# metgrid writes empty met_em files while reporting success. Fixed in WPS 4.7.0.
sed -i -E "s/^(FFLAGS|F77FLAGS)([[:space:]]*=.*)$/\\1\\2 -finit-logical=false/" configure.wps

# Fail loudly rather than silently building a metgrid.exe that writes nothing.
grep -qE "^FFLAGS[[:space:]]*=.*-finit-logical=false" configure.wps \
  || { echo "Failed to patch FFLAGS in configure.wps"; exit 1; }

./compile
popd

[[ -f "$WRF_DIR/main/real.exe" ]] || { echo "WRF real.exe failed to build"; exit 1; }
[[ -f "$WRF_DIR/main/wrf.exe" ]] || { echo "WRF wrf.exe failed to build"; exit 1; }
[[ -f "$WPS_DIR/metgrid.exe" ]] || { echo "WPS metgrid.exe failed to build"; exit 1; }
[[ -f "$WPS_DIR/geogrid.exe" ]] || { echo "WPS geogrid.exe failed to build"; exit 1; }
[[ -f "$WPS_DIR/ungrib.exe" ]] || { echo "WPS ungrib.exe failed to build"; exit 1; }
