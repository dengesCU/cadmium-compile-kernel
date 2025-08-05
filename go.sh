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

echo $VERSION > $CADMIUMROOT/latest_stable.txt

