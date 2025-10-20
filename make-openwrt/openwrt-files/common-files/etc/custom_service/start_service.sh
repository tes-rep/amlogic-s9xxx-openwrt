#!/bin/bash
#========================================================================================
#  HOUJIE-WRT - Custom Startup Services
#  File: /etc/custom_service/start_service.sh
#  Purpose: Run device-specific startup routines (LED, fan, swap, resize, etc.)
#  License: GPLv2
#========================================================================================

LOG_FILE="/tmp/houjie_start_service.log"
log() { echo "[$(date '+%Y.%m.%d %H:%M:%S')] $1" >>"$LOG_FILE"; }

log "=== HOUJIE-WRT Startup Service ==="

#------------------------------------------------------------
# Detect Device Type (.dtb)
#------------------------------------------------------------
FDT_FILE=""
[[ -f /etc/ophub-release ]] && FDT_FILE=$(grep -oE 'meson.*dtb' /etc/ophub-release)
[[ -z "$FDT_FILE" && -f /boot/uEnv.txt ]] && FDT_FILE=$(grep -E '^FDT=.*\.dtb$' /boot/uEnv.txt | sed -E 's#.*/##')
[[ -z "$FDT_FILE" && -f /boot/armbianEnv.txt ]] && FDT_FILE=$(grep -E '^fdtfile=.*\.dtb$' /boot/armbianEnv.txt | sed -E 's#.*/##')
log "Detected FDT file: ${FDT_FILE:-not found}"

#------------------------------------------------------------
# Detect Disk and Data Partition Path
#------------------------------------------------------------
ROOT_PTNAME=$(df -h /boot | awk 'END{print $1}' | awk -F '/' '{print $3}')
if [[ -n "$ROOT_PTNAME" ]]; then
    case "$ROOT_PTNAME" in
        mmcblk?p[0-9]*) DISK="${ROOT_PTNAME%p*}"; PFX="p" ;;
        nvme?n?p[0-9]*) DISK="${ROOT_PTNAME%p*}"; PFX="p" ;;
        [hs]d[a-z][0-9]*) DISK="${ROOT_PTNAME%%[0-9]*}"; PFX="" ;;
        *) log "Unrecognized root partition: $ROOT_PTNAME";;
    esac
    [[ -n "$DISK" ]] && PART_PATH="/mnt/${DISK}${PFX}4"
    log "Disk: ${DISK:-unknown}, Data path: ${PART_PATH:-none}"
else
    log "Unable to detect root partition."
fi

#------------------------------------------------------------
# Network Optimization
#------------------------------------------------------------
[[ -x /usr/sbin/balethirq.pl ]] && { perl /usr/sbin/balethirq.pl &>/dev/null; log "Network IRQ optimization applied."; }

#------------------------------------------------------------
# LED and Display Controls
#------------------------------------------------------------
if [[ -x /usr/sbin/openwrt-openvfd && -f /etc/config/openvfd ]]; then
    BOX_ID=$(uci -q get openvfd.config.boxid)
    ENABLED=$(uci -q get openvfd.config.enabled)
    [[ "$ENABLED" == "1" ]] && { openwrt-openvfd "$BOX_ID" &; log "OpenVFD started (BoxID=$BOX_ID)."; }
fi

[[ -x /usr/bin/rgb-vplus ]] && { rgb-vplus --RedName=RED --GreenName=GREEN --BlueName=BLUE &; log "RGB LED (vplus) started."; }

#------------------------------------------------------------
# Fan Control
#------------------------------------------------------------
[[ -x /usr/bin/pwm-fan.pl ]] && { perl /usr/bin/pwm-fan.pl &; log "PWM Fan service started."; }

#------------------------------------------------------------
# SATA LED Monitor (A311D)
#------------------------------------------------------------
[[ -x /usr/bin/oes_sata_leds.sh ]] && { /usr/bin/oes_sata_leds.sh >/var/log/oes-sata-leds.log 2>&1 &; log "SATA LED monitor active."; }

#------------------------------------------------------------
# Auto Expand Root Filesystem
#------------------------------------------------------------
if [[ -f /root/.todo_rootfs_resize && $(< /root/.todo_rootfs_resize) == "yes" ]]; then
    openwrt-tf &>/dev/null
    log "Root filesystem auto-resize attempted."
fi

#------------------------------------------------------------
# Enable Swap if Available
#------------------------------------------------------------
SWAP_FILE="${PART_PATH}/.swap/swapfile"
if [[ -f "$SWAP_FILE" ]]; then
    LOOP=$(losetup -f)
    if [[ -n "$LOOP" ]]; then
        losetup "$LOOP" "$SWAP_FILE" && swapon "$LOOP" \
            && log "Swap enabled on $LOOP." \
            || { log "Swap setup failed."; losetup -d "$LOOP" 2>/dev/null; }
    else
        log "No free loop device for swap."
    fi
else
    log "No swap file found at ${SWAP_FILE}."
fi

#------------------------------------------------------------
log "Startup process complete."
exit 0
