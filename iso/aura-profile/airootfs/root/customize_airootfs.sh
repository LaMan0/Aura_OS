#!/usr/bin/env bash
set -euo pipefail

id aura >/dev/null 2>&1 || useradd --create-home --groups audio,video,storage,optical --shell /bin/bash aura
passwd --lock aura

install -d -o aura -g aura /home/aura/Desktop
install -m 0644 -o aura -g aura \
  /etc/skel/Desktop/AuraOS-prototype.txt \
  /home/aura/Desktop/AuraOS-prototype.txt

systemctl enable NetworkManager.service
systemctl enable lightdm.service
ln -sfn /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
