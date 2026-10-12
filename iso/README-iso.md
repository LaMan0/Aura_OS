# iso/ — profil archiso « Live & Play »

Ce dossier est la racine du **profil archiso** consommé par [`scripts/build-iso.sh`](../scripts/build-iso.sh).
`build-iso.sh` y injecte automatiquement les scripts (`aura-perf-detect`, `aura-update`,
`aura-run`), les unités systemd (`../systemd/`) et les fichiers de configuration (`../etc/aura/`).

## Structure attendue du profil

```
iso/aura-profile/
├── profiledef.sh              métadonnées de l'image (nom, arch, boot modes)
├── packages.x86_64            liste des paquets installés dans l'image
├── pacman.conf                dépôts utilisés pour le build
├── efiboot/                   entrée EFI (systemd-boot / shim)
├── syslinux/                  configuration BIOS Legacy (isolinux)
└── airootfs/
    ├── etc/
    │   ├── aura/              ← copié depuis ../etc/aura/
    │   ├── systemd/system/    ← copié depuis ../systemd/
    │   └── sddm.conf.d/       auto-login sur la session aura-shell
    ├── usr/lib/aura/bin/      ← copié depuis ../scripts/
    └── usr/share/aura/        thèmes, table des émulateurs, mappings manettes
```

## `profiledef.sh` (extrait de référence)

```bash
iso_name="AuraOS"
iso_label="AURAOS_$(date +%Y%m)"
iso_publisher="AuraOS-Project"
iso_application="AuraOS Live & Play"
iso_version="$(date +%Y.%m.%d)"
install_dir="aura"
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.grub.esp' 'uefi-x64.systemd-boot.esp')
arch="x86_64"
file_permissions=(["/etc/shadow"]="0:0:400" ["/usr/lib/aura/bin/aura-perf-detect"]="0:0:755")
```

## `packages.x86_64` (socle minimal)

```
base linux-firmware mesa vulkan-intel vulkan-radeon
systemd xfce4 xfce4-goodies greetd qt6-base qt6-declarative
gamescope gamemode bubblewrap zram-tools polkit
wine-ge-custom dxvk vkd3d-proton heroic-games-launcher steam-native-runtime
minisign zsync rsync curl jq calamares grub efibootmgr ntfs-3g
librewolf libreoffice-fresh
```

## Vérifications avant publication de l'ISO

1. Boot UEFI **et** BIOS dans QEMU (`qemu-system-x86_64 -cdrom out/*.iso`).
2. L'UI Gaming démarre sans terminal visible, à la manette.
3. L'installeur propose bien les 2 modes et refuse un dual-boot si &lt; 40 Go libres.
4. `aura-perf-detect detect` fonctionne dans la session Live.
