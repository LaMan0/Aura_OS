#!/usr/bin/env bash

  # On ne s'arrête pas sur les erreurs de liens déjà existants
  id aura >/dev/null 2>&1 || useradd --create-home --groups audio,video,storage,optical --shell
  /bin/bash aura
  passwd --lock aura || true

  install -d -o aura -g aura /home/aura/Desktop
  install -m 0644 -o aura -g aura \
    /etc/skel/Desktop/AuraOS-prototype.txt \
    /home/aura/Desktop/AuraOS-prototype.txt || true

  # Activation des services avec protection contre les doublons
  systemctl enable NetworkManager.service || true
  systemctl enable lightdm.service || true
  ln -sfn /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target || true