#!/usr/bin/env bash
# Runs a small real case with the installed package: ungrib, metgrid, real and
# wrf, on a 10x10 domain at 10 km over Queensland for 24 hours. The namelists
# are in tests/case/. The data is too large for the repository, so it is
# downloaded once: geo_em.d01.nc (so geogrid and the geography data aren't
# needed) and five NCEP FNL analyses (00Z to 00Z, 2022-07-22 to 23) subset to
# the domain. See tests/README.md.
#
# Run from a clean debian:trixie-slim with openmethane-wrf installed, with
# /opt/wrf/main and /opt/wps on PATH.

set -euo pipefail

case_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/case" && pwd)"

# the test data bundle, and its checksum
TEST_DATA_URL="${TEST_DATA_URL:-https://openmethane.s3.amazonaws.com/tests/wrf/wrf-test-data.20261124.tar.gz}"
TEST_DATA_SHA256="${TEST_DATA_SHA256:-a1e3df7b54b66f7ea1848daab2c3d2c67526a54f47e1504d4090fce23fb8c314}"
data_dir="${TEST_DATA_DIR:-/tmp/wrf-test-data}"

if [ ! -f "$data_dir/geo_em.d01.nc" ]; then
  echo "Fetching test data"
  mkdir -p "$data_dir"
  curl -fsSL --retry 3 -o "$data_dir.tar.gz" "$TEST_DATA_URL"
  echo "$TEST_DATA_SHA256  $data_dir.tar.gz" | sha256sum -c -
  tar -xzf "$data_dir.tar.gz" -C "$data_dir"
  rm "$data_dir.tar.gz"
fi
# Set CASE_WORKDIR to an empty directory to keep the outputs
if [ -n "${CASE_WORKDIR:-}" ]; then
  work="$CASE_WORKDIR"
else
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
fi
cd "$work"

expect() {  # expect <min bytes> <file>
  [ -s "$2" ] && [ "$(stat -c %s "$2")" -ge "$1" ] || { echo "FAILED: $2 is missing or smaller than $1 bytes"; exit 1; }
}

echo "== ungrib"
cp "$case_dir/namelist.wps" "$data_dir/geo_em.d01.nc" .
ln -s /opt/wps/ungrib/Variable_Tables/Vtable.GFS Vtable
link_grib.csh "$data_dir"/gdas1.fnl0p25.*.grib2
ungrib.exe > ungrib.log 2>&1 || { cat ungrib.log; exit 1; }
grep -q "Successful completion of ungrib" ungrib.log || { cat ungrib.log; exit 1; }
ls FILE:*

echo "== metgrid"
mkdir metgrid
ln -s /opt/wps/metgrid/METGRID.TBL metgrid/METGRID.TBL
metgrid.exe > metgrid.log 2>&1 || { cat metgrid.log; exit 1; }
grep -q "Successful completion of metgrid" metgrid.log || { cat metgrid.log; exit 1; }
# met_em files with no fields are tiny: metgrid once wrote them while reporting success
[ "$(ls met_em.d01.*.nc | wc -l)" -eq 5 ] || { echo "FAILED: expected 5 met_em files"; exit 1; }
for f in met_em.d01.*.nc; do expect 100000 "$f"; done

echo "== real"
mkdir run && cd run
ln -s /opt/wrf/run/* .
rm -f namelist.input *.exe
ln -s ../met_em.d01.*.nc .
cp "$case_dir/namelist.input" .
ln -s /opt/wrf/main/real.exe /opt/wrf/main/wrf.exe .
mpirun -np 1 ./real.exe > real.log 2>&1 || { cat real.log rsl.error.0000; exit 1; }
grep -q "SUCCESS COMPLETE REAL_EM INIT" rsl.out.0000 || { cat rsl.error.0000; exit 1; }
expect 100000 wrfinput_d01
expect 100000 wrfbdy_d01

echo "== wrf"
mpirun -np 1 ./wrf.exe > wrf.log 2>&1 || { cat wrf.log rsl.error.0000; exit 1; }
grep -q "SUCCESS COMPLETE WRF" rsl.out.0000 || { cat rsl.error.0000; exit 1; }
expect 100000 wrfout_d01_2022-07-22_00:00:00

echo "PASSED: ungrib, metgrid, real and wrf ran the case"
