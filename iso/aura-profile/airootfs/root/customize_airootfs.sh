#!/usr/bin/env bash
# Personnalisation du système Live AuraOS (exécuté dans l'airootfs par mkarchiso).
# Ce script tourne dans l'environnement Live pendant le build : on ne s'arrête
# pas sur les erreurs non bloquantes (liens déjà présents, etc.).

# Compte de session Live « aura », sans mot de passe (verrouillé).
id aura >/dev/null 2>&1 || useradd --create-home \
  --groups audio,video,storage,optical,wheel --shell /bin/bash aura || true
passwd --lock aura || true

install -d -o aura -g aura /home/aura/Desktop || true
install -m 0644 -o aura -g aura \
  /etc/skel/Desktop/AuraOS-prototype.txt \
  /home/aura/Desktop/AuraOS-prototype.txt || true
install -m 0644 -o aura -g aura /etc/skel/.xinitrc /home/aura/.xinitrc || true

# Configuration de session (autostart du fond d'écran AuraOS, etc.).
# On la copie explicitement : certains utilitaires ne reprennent pas tous les
# fichiers cachés de /etc/skel.
install -d -o aura -g aura /home/aura/.config || true
if [[ -d /etc/skel/.config ]]; then
  cp -a /etc/skel/.config/. /home/aura/.config/ 2>/dev/null || true
  chown -R aura:aura /home/aura/.config 2>/dev/null || true
fi

# Activation des services. On utilise `systemctl enable` plutôt que de livrer les
# liens .wants : les symlinks ne survivent pas à un commit depuis Windows.
systemctl enable NetworkManager.service || true
systemctl enable lightdm.service || true
ln -sfn /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target || true
