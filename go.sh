#!/bin/bash
KERNEL_CONF=/config.arm64
PATCHES_DIR=/patches
CADMIUMROOT=/cadmium

set -e

# url to latest stable kernel
#URL=$(curl -sL https://www.kernel.org/ | grep "Download complete tarball" | head -n2 | tail -n1 | tr '"' ' ' | awk '{print $3}')
# url to latest release (big download button on kernel.org)
URL=$(curl -sL https://www.kernel.org/ | grep "latest_link" -A 1 | tail -n1 | tr '"' ' ' | awk '{print $3}')

# version of latest stable kernel
VERSION=$(echo $URL | tr '-' ' ' | awk '{print $2}')
VERSION=${VERSION::-7}

# How many threads should be used for building kernel
THREADS=$(echo "if ($(nproc) > 2) $(nproc) - 2 else 1" | bc)

# Misc. params
ARCH=arm64
ARCH_UNAME=aarch64
ARCH_DEB=arm64
ARCH_ALARM=aarch64

mkdir -p $CADMIUMROOT/tmp
touch $CADMIUMROOT/latest_stable.txt

if [ $VERSION == "$(cat $CADMIUMROOT/latest_stable.txt)" ]; then
  echo "No new version available. Kernel $VERSION is up to date."
  echo "Nothing to do."
  exit 0
fi

echo "New version ($VERSION) available!"

cd $CADMIUMROOT/tmp

echo "Downloading..."
curl -L $URL -o Linux-archive

echo "Extracting..."
rm -rf linux-$ARCH
mkdir linux-$ARCH
bsdtar xf Linux-archive --strip-components=1 -C linux-$ARCH

cd linux-$ARCH

echo "Applying patches..."
for x in $(ls $PATCHES_DIR/*.patch); do
	echo "Applying $x"
	patch -p1 --forward < $x
done
for x in $(ls $PATCHES_DIR/*.common_patch); do
	echo "Applying $x"
	patch -p1 --forward < $x
done

cp $KERNEL_CONF .config
cp $KERNEL_CONF ${KERNEL_CONF}~

make oldconfig LLVM=1 ARCH=$ARCH
#make nconfig LLVM=1 # if you want to customize config just uncomment this

cp .config $KERNEL_CONF

echo "Bulding kernel for $ARCH in $(pwd) with $THREADS threads"
time make -j"$THREADS" LLVM=1 ARCH=$ARCH

echo "Packaging kernel for depthcharge machines"

[ -z "$CADMIUMROOT" ] && exit 1

VBUTIL_KERNEL=""
if which vbutil_kernel >/dev/null 2>&1; then
	VBUTIL_KERNEL="vbutil_kernel"
elif which futility >/dev/null 2>&1; then
	VBUTIL_KERNEL="futility vbutil_kernel"
else
	echo "vbutil_kernel not found"
	exit 1
fi


cd "$CADMIUMROOT/tmp/linux-$ARCH"

if [ "$ARCH" = "arm64" ]; then
	COMPRESSION="lz4"
	IMAGE="c_linux.lz4"
	lz4 -z --best -f "arch/$ARCH/boot/Image" c_linux.lz4
else
	COMPRESSION="none"
	IMAGE="arch/arm/boot/zImage"
fi

echo 'console=ttyMSM0,115200 console=ttyS2,115200 console=ttyS0,115200 console=tty1 rootwait rw fbcon=logo-pos:center,logo-count:1 loglevel=7 root=PARTUUID=%U/PARTNROFF=2' >> cmdline
echo 'console=ttyMSM0,115200 console=ttyS2,115200 console=ttyS0,115200 console=tty1 rootwait rw fbcon=logo-pos:center,logo-count:1 loglevel=7 root=PARTUUID=%U/PARTNROFF=1' >> cmdline.p2

# https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/linux-aarch64/PKGBUILD
for B in veyron elm gru kukui trogdor; do
	DTBS="$DTBS $(find arch/$ARCH/boot/dts -name \*${B}\*.dtb)"
done

echo $DTBS | "$CADMIUMROOT/loader/depthcharge/generate_chromebook_its.sh" "$IMAGE" "$ARCH" "$COMPRESSION" > kernel.its

mkimage -D "-I dts -O dtb -p 2048" -f kernel.its vmlinux.uimg

dd if=/dev/zero of=bootloader.bin bs=512 count=1
$VBUTIL_KERNEL --pack vmlinux.kpart \
	--version 1 \
	--vmlinuz vmlinux.uimg \
	--arch arm \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config cmdline \
	--bootloader bootloader.bin

cp vmlinux.kpart "$CADMIUMROOT/tmp/"
cp vmlinux.kpart /out/vmlinux-$VERSION-cadmium.kpart
#dd if="vmlinux.kpart" of="$KERNPART" conv=fsync

echo "Finished packaging for depthcharge"

echo "Building kernel modules.."

sudo make -C $CADMIUMROOT/tmp/linux-arm64/ INSTALL_MOD_PATH="/out" modules_install

tar -cf /out/linux-$VERSION-cadmium-modules.xz /out/lib
rm /out/lib -r

echo "Done"

echo $VERSION > $CADMIUMROOT/latest_stable.txt

