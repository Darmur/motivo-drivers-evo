#!/bin/bash

CPU=8
KERNEL_VERSION="6.12.47"

# ---- Version configuration ----
# SOURCE_SET: source_files subdirectory (shared across point releases)
# When 6.12.48 arrives, add a case entry pointing to the same SOURCE_SET.
# When 6.18 arrives, create source_files/6.18.y/ and add a new case entry.

case $KERNEL_VERSION in
    "6.12.47")
      KERNEL_COMMIT="6d1da66a7b1358c9cd324286239f37203b7ce25c"
      SOURCE_SET="6.12.47"
      ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_BASE="${SCRIPT_DIR}/../source_files/${SOURCE_SET}"

echo "!!!  Build modules for kernel ${KERNEL_VERSION}  !!!"
echo "!!!  Source set: ${SOURCE_SET}  !!!"

# ---- Download and extract kernel source ----
echo "!!!  Download kernel hash info  !!!"
wget -N https://raw.githubusercontent.com/raspberrypi/rpi-firmware/${KERNEL_COMMIT}/git_hash
GIT_HASH="$(cat git_hash)"
rm git_hash

echo "!!!  Download kernel source  !!!"
wget https://github.com/raspberrypi/linux/archive/${GIT_HASH}.tar.gz

echo "!!!  Extract kernel source  !!!"
rm -rf linux-${KERNEL_VERSION}-v7l+/
tar xvzf ${GIT_HASH}.tar.gz
rm ${GIT_HASH}.tar.gz
mv linux-${GIT_HASH}/ linux-${KERNEL_VERSION}-v7l+/

# ---- Inject Motivo source files ----
echo "!!!  Injecting Motivo customisations  !!!"
TREE="linux-${KERNEL_VERSION}-v7l+"
PANEL_DIR="${TREE}/drivers/gpu/drm/panel"
OVERLAY_DIR="${TREE}/arch/arm/boot/dts/overlays"

# Panel driver
echo "  -> panel-dsi-mt.c"
cp ${SRC_BASE}/panel/panel-dsi-mt.c "${PANEL_DIR}/"

# Kconfig (insert fragment before endmenu if not present)
if ! grep -q "DRM_PANEL_DSI_MT" "${PANEL_DIR}/Kconfig"; then
    echo "  -> Kconfig entry"
    sed -i '/^endmenu$/d' "${PANEL_DIR}/Kconfig"
    cat "${SRC_BASE}/panel/Kconfig.inject" >> "${PANEL_DIR}/Kconfig"
    echo "endmenu" >> "${PANEL_DIR}/Kconfig"
fi

# Makefile (append if not present)
if ! grep -q "panel-dsi-mt" "${PANEL_DIR}/Makefile"; then
    echo "  -> Makefile entry"
    echo 'obj-$(CONFIG_DRM_PANEL_DSI_MT) += panel-dsi-mt.o' >> "${PANEL_DIR}/Makefile"
fi

# Device tree overlays
echo "  -> overlay DTS files"
cp ${SRC_BASE}/overlays/*.dts "${OVERLAY_DIR}/"

# Overlay Makefile (inject build targets if not present)
OV_MK="${OVERLAY_DIR}/Makefile"
DTBO_PATTERN=$'^\t.*\.dtbo'
OVERLAYS_TO_ADD=()
for dts in ${SRC_BASE}/overlays/*.dts; do
    name=$(basename "$dts" -overlay.dts)
    dtbo="${name}.dtbo"
    if ! grep -q "${dtbo}" "${OV_MK}"; then
        OVERLAYS_TO_ADD+=("${dtbo}")
    fi
done

if [ ${#OVERLAYS_TO_ADD[@]} -gt 0 ]; then
    LAST=$(grep -n "${DTBO_PATTERN}" "${OV_MK}" | tail -1 | cut -d: -f1)
    LASTLINE=$(sed -n "${LAST}p" "${OV_MK}")
    if [[ ! "$LASTLINE" =~ \\$ ]]; then
        sed -i "${LAST}s/\$/ \\\\/" "${OV_MK}"
    fi

    COUNT=${#OVERLAYS_TO_ADD[@]}
    IDX=0
    for dtbo in "${OVERLAYS_TO_ADD[@]}"; do
        IDX=$((IDX + 1))
        echo "  -> overlay target: ${dtbo}"
        LAST=$(grep -n "${DTBO_PATTERN}" "${OV_MK}" | tail -1 | cut -d: -f1)
        if [ "$IDX" -lt "$COUNT" ]; then
            sed -i "${LAST}a\\	${dtbo} \\\\" "${OV_MK}"
        else
            sed -i "${LAST}a\\	${dtbo}" "${OV_MK}"
        fi
    done
fi

# USB audio quirks
echo "  -> sound_usb/quirks.c"
cp ${SRC_BASE}/sound_usb/quirks.c ${TREE}/sound/usb/

# ---- Copy tree for 64-bit build ----
echo "!!!  Copy source files for other variants  !!!"
rm -rf linux-${KERNEL_VERSION}-v8+/
cp -r linux-${KERNEL_VERSION}-v7l+/ linux-${KERNEL_VERSION}-v8+/

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

# Overlays (architecture independent, from v7l build)
cp linux-${KERNEL_VERSION}-v7l+/arch/arm/boot/dts/overlays/motivo*.dtbo ${ARCHIVE}/boot/overlays/
cp linux-${KERNEL_VERSION}-v7l+/arch/arm/boot/dts/overlays/es9039q2m*.dtbo ${ARCHIVE}/boot/overlays/

# Modules per architecture
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
