#!/usr/bin/env bash
# Packages the runtime files of a finished build as openmethane-wrf, at the
# paths the build put them. Usage: package.sh <deb-version> <outdir>
#
# In the package: wrf.exe and real.exe, the data files of run/, the WPS
# programs and tables. Not in it: sources, object files, ndown.exe
# and tc.exe. Symlinks are followed (some files in run/ link into the build
# tree, and the WPS programs link into their src/ folders), except the
# program links in run/, which are left out.

set -euo pipefail

[ "$#" -eq 2 ] || { echo "Usage: $0 <deb-version> <outdir>" >&2; exit 2; }
version="$1" outdir="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WRF_DIR="${WRF_DIR:-/opt/wrf}"
WPS_DIR="${WPS_DIR:-/opt/wps}"

mapfile -t run_files < <(find "$WRF_DIR/run" -mindepth 1 -maxdepth 1 ! -name '*.exe' | sort)

# mpich provides mpirun and csh runs link_grib.csh. Nothing links against them.
"$here/build-deb.sh" --dereference \
  openmethane-wrf "$version" \
  "Open Methane WRF and WPS: wrf.exe, real.exe, the WPS programs" \
  "$outdir" \
  "$WRF_DIR/main/wrf.exe" "$WRF_DIR/main/real.exe" \
  "${run_files[@]}" \
  "$WPS_DIR/geogrid.exe" "$WPS_DIR/ungrib.exe" "$WPS_DIR/metgrid.exe" \
  "$WPS_DIR/link_grib.csh" \
  "$WPS_DIR"/geogrid/GEOGRID.TBL* \
  "$WPS_DIR"/metgrid/METGRID.TBL* \
  "$WPS_DIR/ungrib/Variable_Tables" \
  -- mpich csh
