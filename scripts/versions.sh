# The versions of everything the build downloads. Sourced by the build scripts
# and read by CI. Each tarball is verified against scripts/checksums.sha256,
# so changing a version means adding its checksum there too.
WRF_VERSION="${WRF_VERSION:-4.5.1}"
WPS_VERSION="${WPS_VERSION:-4.5}"
JASPER_VERSION="${JASPER_VERSION:-4.2.5}"
