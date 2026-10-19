# syntax=docker/dockerfile:1
# RTEMS 7 SPARC cross toolchain and erc32 BSP, built with the RTEMS Source
# Builder, RTEMS and rtems_waf from their Git main branches.
# Applications are not part of the image; mount them at /work.

ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION} AS toolchain

LABEL org.opencontainers.image.title="rtems7-tools" \
      org.opencontainers.image.description="RTEMS 7 SPARC cross toolchain and erc32 BSP built from Git main"

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1

# python-is-python3: the RTEMS tools use "#!/usr/bin/env python".
# python3-dev: Python.h for the GDB build.
# libreadline-dev: the SIS simulator links GNU readline.
# install-info: RSB registers info pages at install time, and it is not
# pulled in by texinfo when recommends are disabled.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential g++ git make ninja-build ccache \
        python3 python3-dev python-is-python3 \
        unzip bison flex texinfo zlib1g-dev pkg-config \
        curl xz-utils bzip2 patch ca-certificates \
        libexpat1-dev libncurses-dev libreadline-dev \
        bsdextrautils file install-info \
    && rm -rf /var/lib/apt/lists/* \
    && command -v rev && command -v install-info

# The RSB must not run as root. Everything lives under /opt/rtems, which is
# world-readable so the image also works with "docker run --user <host uid>".
RUN groupadd --gid 10001 rtems \
    && useradd --uid 10001 --gid rtems --create-home --shell /bin/bash rtems \
    && mkdir -p /opt/rtems \
    && chown rtems:rtems /opt/rtems
USER rtems
WORKDIR /opt/rtems

ENV RTEMS_PREFIX=/opt/rtems/7 \
    RTEMS_SUPPORT=/opt/rtems/app-support \
    RTEMS_SRC=/opt/rtems/src

# Cross toolchain. Two BuildKit caches survive a failed build: the downloaded
# sources and a ccache of compiled objects, so a retry does not download
# everything again. The RSB tree and build files are removed afterwards to
# keep the image small.
RUN --mount=type=cache,target=/opt/rtems/dl,uid=10001,gid=10001 \
    --mount=type=cache,target=/opt/rtems/ccache,uid=10001,gid=10001 \
    export CCACHE_DIR=/opt/rtems/ccache CCACHE_MAXSIZE=5G PATH=/usr/lib/ccache:${PATH} && \
    git clone https://gitlab.rtems.org/rtems/tools/rtems-source-builder.git ${RTEMS_SRC}/rsb && \
    cd ${RTEMS_SRC}/rsb/rtems && \
    rm -rf sources && ln -s /opt/rtems/dl sources && \
    ok=0 && \
    for i in 1 2 3 4 5 6 7 8 9 10; do \
        ../source-builder/sb-set-builder --source-only-download 7/rtems-sparc && ok=1 && break; \
        echo "download attempt $i failed, retrying"; sleep 15; \
    done && \
    [ "$ok" = 1 ] && \
    { ../source-builder/sb-set-builder --log=/tmp/rsb.log --prefix=${RTEMS_PREFIX} 7/rtems-sparc \
        || { tail -n 80 /tmp/rsb.log; exit 1; }; } && \
    ccache --show-stats && \
    cd / && rm -rf ${RTEMS_SRC}

# Added only after the build so the RSB never picks up half-installed tools.
ENV PATH=${RTEMS_PREFIX}/bin:${PATH}
RUN sparc-rtems7-gcc --version && command -v rtems-run

# BSP stage. Rebuild only this part, keeping the toolchain, with:
#   docker build --no-cache-filter bsp -t rtems7-docker .
FROM toolchain AS bsp

ENV HOME=/tmp

RUN git clone https://gitlab.rtems.org/rtems/rtos/rtems.git ${RTEMS_SRC}/rtems && \
    cd ${RTEMS_SRC}/rtems && \
    echo "[sparc/erc32]" > config.ini && \
    ./waf configure --prefix=${RTEMS_PREFIX} && \
    ./waf && \
    ./waf install && \
    mkdir -p ${RTEMS_SUPPORT} && \
    cp waf ${RTEMS_SUPPORT}/waf && \
    git clone --depth 1 https://gitlab.rtems.org/rtems/tools/rtems_waf.git ${RTEMS_SUPPORT}/rtems_waf && \
    { echo "rtems $(git rev-parse HEAD)"; \
      echo "rtems_waf $(git -C ${RTEMS_SUPPORT}/rtems_waf rev-parse HEAD)"; } > ${RTEMS_SUPPORT}/BUILDINFO && \
    rm -rf ${RTEMS_SUPPORT}/rtems_waf/.git && \
    test -d ${RTEMS_PREFIX}/sparc-rtems7/erc32 && \
    test -x ${RTEMS_SUPPORT}/waf && \
    cd / && rm -rf ${RTEMS_SRC}

COPY --chmod=755 <<'EOF' /usr/local/bin/rtems-app
#!/bin/sh
set -eu

SUPPORT=/opt/rtems/app-support
OUT=build/sparc-rtems7-erc32

die() { echo "error: $*" >&2; exit 1; }

prepare() {
  [ -f wscript ] || die "no wscript in $PWD, mount the application at /work"
  [ -w . ] || die "$PWD is not writable, pass --user \"\$(id -u):\$(id -g)\""
  cp -f "$SUPPORT/waf" waf
  rm -rf rtems_waf
  cp -r "$SUPPORT/rtems_waf" rtems_waf
}

build() {
  prepare
  ./waf configure --rtems="$RTEMS_PREFIX" --rtems-bsp=sparc/erc32
  ./waf
}

run() {
  build
  exe="$OUT/${EXE:-hello.exe}"
  [ -f "$exe" ] || die "$exe not found, pass -e EXE=<name>.exe to docker run"
  exec rtems-run --rtems-bsps=erc32-sis "$exe"
}

case "${1:-run}" in
  run)   run ;;
  build) build ;;
  shell) prepare; exec bash ;;
  clean) rm -rf build .lock-waf* .waf* __pycache__ ;;
  info)  cat "$SUPPORT/BUILDINFO"; sparc-rtems7-gcc --version | head -n 1 ;;
  *)     exec "$@" ;;
esac
EOF

WORKDIR /work
ENTRYPOINT ["rtems-app"]
CMD ["run"]
