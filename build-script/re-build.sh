#!/bin/bash

CPU=8
KERNEL_VERSION="6.12.74"

case $KERNEL_VERSION in
    "6.12.74") SOURCE_SET="6.12.74" ;;
    "6.12.47") SOURCE_SET="6.12.47" ;;
    "6.6.62") SOURCE_SET="6.6.62" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_BASE="${SCRIPT_DIR}/../source_files/${SOURCE_SET}"

echo "!!!  Rebuild modules for kernel ${KERNEL_VERSION}  !!!"

# Re-inject source files (in case they changed since last build)
echo "!!!  Re-injecting source files from ${SOURCE_SET}  !!!"
for tree in linux-${KERNEL_VERSION}-v7l+ linux-${KERNEL_VERSION}-v8+; do
    cp ${SRC_BASE}/panel/panel-dsi-mt.c ${tree}/drivers/gpu/drm/panel/
    cp ${SRC_BASE}/sound_usb/quirks.c ${tree}/sound/usb/
done
cp ${SRC_BASE}/overlays/*.dts linux-${KERNEL_VERSION}-v7l+/arch/arm/boot/dts/overlays/

# ---- Build 32-bit ----
echo "!!!  Build CM4 32-bit kernel and modules  !!!"
cd linux-${KERNEL_VERSION}-v7l+/
make -j${CPU} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcm2711_defconfig
./scripts/config --module CONFIG_DRM_PANEL_DSI_MT
make -j${CPU} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules dtbs
cd ..
echo "!!!  CM4 32-bit build done  !!!"
echo "-------------------------"

# ---- Build 64-bit ----
echo "!!!  Build CM4 64-bit kernel and modules  !!!"
cd linux-${KERNEL_VERSION}-v8+/
make -j${CPU} ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2711_defconfig
./scripts/config --module CONFIG_DRM_PANEL_DSI_MT
make -j${CPU} ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules dtbs
cd ..
echo "!!!  CM4 64-bit build done  !!!"
echo "-------------------------"

# ---- Compress and package ----
echo "!!!  Compress modules with xz  !!!"
for tree in linux-${KERNEL_VERSION}-v7l+ linux-${KERNEL_VERSION}-v8+; do
    xz -f ${tree}/drivers/gpu/drm/panel/panel-dsi-mt.ko
    xz -f ${tree}/sound/usb/snd-usb-audio.ko
done

echo "!!!  Creating archive  !!!"
ARCHIVE="modules-rpi-${KERNEL_VERSION}-motivo"
rm -rf ${ARCHIVE}/
mkdir -p ${ARCHIVE}/boot/overlays

for variant in ${KERNEL_VERSION}-v7l+ ${KERNEL_VERSION}-v8+; do
    mkdir -p ${ARCHIVE}/lib/modules/${variant}/kernel/drivers/gpu/drm/panel/
    mkdir -p ${ARCHIVE}/lib/modules/${variant}/kernel/sound/usb/
done

cp linux-${KERNEL_VERSION}-v7l+/arch/arm/boot/dts/overlays/motivo*.dtbo ${ARCHIVE}/boot/overlays/
cp linux-${KERNEL_VERSION}-v7l+/arch/arm/boot/dts/overlays/es9039q2m*.dtbo ${ARCHIVE}/boot/overlays/

for tree in linux-${KERNEL_VERSION}-v7l+ linux-${KERNEL_VERSION}-v8+; do
    variant="${tree#linux-}"
    DEST="${ARCHIVE}/lib/modules/${variant}/kernel"
    cp ${tree}/drivers/gpu/drm/panel/panel-dsi-mt.ko.xz ${DEST}/drivers/gpu/drm/panel/
    cp ${tree}/sound/usb/snd-usb-audio.ko.xz ${DEST}/sound/usb/
done

tar -czvf ${ARCHIVE}.tar.gz ${ARCHIVE}/ --owner=0 --group=0
md5sum ${ARCHIVE}.tar.gz > ${ARCHIVE}.md5sum.txt
sha1sum ${ARCHIVE}.tar.gz > ${ARCHIVE}.sha1sum.txt
rm -rf ${ARCHIVE}/
mkdir -p ../output
mv ${ARCHIVE}* ../output/

echo "!!!  Done  !!!"
