# syntax=docker/dockerfile:1
#
# Builds WRF and WPS and packages them as the Debian package openmethane-wrf
# (see README.md). Export the package with
#   docker build --target deb --output type=local,dest=dist .
# The last stage, test, installs the package in a clean image, so a plain
# `docker build .` builds and checks it.
#
# Every build step runs a script from scripts/, which docs/building.md
# describes for a build outside Docker. Versions are in scripts/versions.sh.

# Debian version of the package: <WRF version>-<revision>
ARG DEB_VERSION=0.0.0~development

# ---------------------------------------------------------------------------
# Jasper isn't packaged in Debian trixie (dropped for its CVE history in the
# old 1.9 branch), but WPS's GRIB2 support hard-links against it for JPEG2000
# decoding, so build a current, static copy from source.
FROM debian:trixie-slim AS jasper-builder

RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    ca-certificates \
    curl \
    build-essential \
    cmake

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

COPY scripts/versions.sh scripts/checksums.sha256 scripts/fetch.sh scripts/build_jasper.sh /opt/build/scripts/
RUN /opt/build/scripts/build_jasper.sh

# ---------------------------------------------------------------------------
# WRF in /opt/wrf and WPS in /opt/wps, built where they run
FROM debian:trixie-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install the bare minimum build requirements
RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    ca-certificates \
    curl \
    build-essential \
    m4 \
    csh \
    gfortran \
    libmpich-dev \
    libnetcdf-dev \
    libnetcdff-dev \
    libpng-dev \
    zlib1g-dev

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

COPY --from=jasper-builder /opt/jasper /opt/jasper
ENV JASPER_PREFIX=/opt/jasper

COPY scripts /opt/build/scripts/
RUN /opt/build/scripts/build_wrf.sh

# ---------------------------------------------------------------------------
# openmethane-wrf: the runtime files of the build, where the build put them
FROM builder AS package

RUN <<EOT
apt-get update -qy
apt-get install -qyy -o APT::Install-Recommends=false dpkg-dev
EOT

ARG DEB_VERSION
RUN /opt/build/scripts/package.sh "$DEB_VERSION" /out

# ---------------------------------------------------------------------------
# Only the package, for export with --target deb
FROM scratch AS deb
COPY --from=package /out/*.deb /

# ---------------------------------------------------------------------------
# openmethane-wrf installed into a clean image, which must resolve every
# library and find the programs it needs. Run the CI case in it with
#   docker run --rm -v ./tests:/opt/tests <image> /opt/tests/run-case.sh
FROM debian:trixie-slim AS test

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=bind,from=package,source=/out,target=/debs <<EOT
apt-get update -qy
apt-get install -qyy -o APT::Install-Recommends=false /debs/openmethane-wrf_*.deb
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

# The package doesn't set PATH. This is the PATH the case runs with.
ENV PATH="/opt/wrf/main:/opt/wps:${PATH}"

COPY tests/check-libs.sh tests/check-commands.sh /opt/tests/
RUN /opt/tests/check-libs.sh openmethane-wrf && /opt/tests/check-commands.sh

# Only the case needs these: run-case.sh downloads its data. Installed after
# the checks above, so that nothing they bring in hides a missing dependency.
RUN <<EOT
apt-get update -qy
apt-get install -qyy -o APT::Install-Recommends=false ca-certificates curl
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

CMD ["/opt/tests/run-case.sh"]
