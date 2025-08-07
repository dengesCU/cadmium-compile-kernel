FROM debian

ARG UID="1000"
ARG GID="1000"

ARG DEBIAN_FRONTEND="noninteractive"
ENV TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

RUN \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    libarchive-tools curl wget f2fs-tools cgpt vboot-utils libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf qemu-user-static lld gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu llvm clang u-boot-tools debootstrap bc lz4 bsdmainutils &&\
    mkdir -p /cadmium/loader/depthcharge/

# if still something is missing try libcurses5-dev

COPY go.sh /go.sh
COPY generate_chromebook_its.sh /cadmium/loader/depthcharge/generate_chromebook_its.sh
COPY patches /patches
COPY config.arm64 /config.arm64

VOLUME /out
VOLUME /cadmium

ENTRYPOINT ["/go.sh"]
