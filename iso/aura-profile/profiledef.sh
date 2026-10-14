#!/usr/bin/env bash
# shellcheck disable=SC2034
iso_name="auraos"
iso_label="AURAOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="AuraOS Prototype"
iso_application="AuraOS Live Prototype"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/aura-live-info"]="0:0:755"
  ["/usr/local/bin/aura-set-wallpaper"]="0:0:755"
)
