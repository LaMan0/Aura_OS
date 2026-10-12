# 01 — Architecture globale d'AuraOS

## 1. Choix de la distribution socle

**Décision : Arch Linux minimal + archiso**, reconstruit en image immutable par release.

| Critère | Arch (retenu) | Debian stable | Justification |
|---|---|---|---|
| Fraîcheur Mesa/Vulkan/Proton | ✅ rolling | ❌ (backports partiels) | un OS gaming meurt avec des drivers vieux de 2 ans |
| Outil d'ISO officiel | archiso (simple, documenté) | live-build (complexe) | itération rapide sur l'image |
| Philosophie | proche de SteamOS 3 | proche des distros bureau | modèle mental « console » |
| cgroups v2 / systemd récent | natif | partiel | requis par le game-mode |
| Risque | instabilité rolling | stagnation | mitigé : image figée par release + MAJ A/B |

Sous-ensemble installé (paquets réels) :
`base linux-firmware mesa vulkan-icd-loader systemd xfce4 gamescope gamemode
bubblewrap zram-tools polkit elogind greetd qt6-base qt6-declarative
steam-native-runtime wine-ge-custom dxvk vkd3d-proton heroic-games-launcher
minisign zsync rsync calamares grub efibootmgr ntfs-3g`

## 2. Vue en couches

```
┌────────────────────────────────────────────────────────────────────┐
│  UTILISATEUR (manette / clavier / souris)                          │
├───────────────────────────────┬────────────────────────────────────┤
│  MODE GAMING                  │  MODE BUREAU                       │
│  Aura Shell (Qt6/QML)         │  XFCE ultra-customisé              │
│   ├── Bibliothèque            │   ├── Thunar / Firefox-Librewolf   │
│   ├── Launcher intégré        │   ├── LibreOffice                  │
│   ├── Centre de notifs (MAJ)  │   └── Panneau de config système    │
│   └── Paramètres / Système    │        (aura-settings)             │
├───────────────────────────────┴────────────────────────────────────┤
│  COMPOSITOR — gamescope (Wayland) : résolution interne dynamique,  │
│  VRR, FSR, cap FPS par profil, isolation du flux graphique         │
├────────────────────────────────────────────────────────────────────┤
│  AGENCIEL — couche de compatibilité unifiée                        │
│   aura-run : détection d'exécutable → routing                      │
│   ├── natif Linux (ELF)          ├── Steam (natif / Proton-GE)     │
│   ├── .exe/.msi → Wine/Proton-GE ├── Epic / GOG → Heroic headless  │
│   ├── ROM → émulateurs           └── .sh/.AppImage → bubblewrap    │
│   + DXVK / VKD3D-Proton / MangoHud / gamemode                     │
├────────────────────────────────────────────────────────────────────┤
│  MOTEUR DE PERFORMANCE — aura-perf-detect                          │
│   profils merguez / mid / high · zRAM · governor · cgroups v2      │
│   game-mode (freeze background.slice) · sysctls                    │
├────────────────────────────────────────────────────────────────────┤
│  SYSTÈME                                                          │
│   systemd (cgroups v2) · kernel Linux optimisé (BORE/lacuna ou     │
│   vanilla + sched-ext) · drivers Mesa/NVIDIA · zram · Btrfs/ext4   │
├────────────────────────────────────────────────────────────────────┤
│  MATÉRIEL : CPU x86_64 · GPU Intel/AMD/NVIDIA · NVMe/SATA/eMMC     │
└────────────────────────────────────────────────────────────────────┘
```

## 3. Partitionnement cible (installeur)

```
┌──────────────────────────────────────────────────────────────┐
│ schéma GPT                                                    │
├──────────────┬──────────┬─────────────────────────────────────┤
│ p1  ESP      │  512 Mo  │ FAT32 /boot/efi (shim+grub)         │
│ p2  boot     │  1 Go    │ ext4 /boot (kernel+initramfs A/B)   │
│ p3  rootA    │  20 Go   │ ext4 /  (lecture seule runtime)     │
│ p4  rootB    │  20 Go   │ ext4 /  (slot inactif des MAJ)      │
│ p5  var      │  20+ Go  │ ext4 /var (préfixes Wine, jeux)     │
│ p6  home     │  reste   │ ext4 /home (ou Btrfs @home)         │
│ swapfile     │  2-8 Go  │ sur p6 (zRAM prioritaire)           │
└──────────────┴──────────┴─────────────────────────────────────┘
Dual-boot : la partition Windows existante est conservée ; GRUB os-prober l'ajoute.
Root monté ro (overlay tmpfs pour /etc volatile optionnel) → immutabilité de fait.
```

## 4. Structure du système de fichiers installé

```
/etc/aura/                  configuration machine (cf. etc/aura/)
├── aura.conf               profils, préférences UI, chemins
├── update.conf             dépôt GitHub, canal, clé minisign
└── perf-profile.conf       PROFIL COURANT (généré par aura-perf-detect)

/usr/lib/aura/              code exécutable du système (paquet aura-core)
├── bin/aura-perf-detect    profiler matériel + game-mode
├── bin/aura-update         client MAJ GitHub
├── bin/aura-run            lanceur universel de jeux
├── bin/aura-shell          l'UI Gaming (binaire Qt6)
└── lib/aura/               modules : detect-hw.sh, zram.sh, cgroup.sh, proton-map.sh

/usr/share/aura/
├── themes/                 tokens visuels (clair/sombre/merguez-lite)
├── controllerdb/           mappings SDL manettes
└── emulators/              table ROM → émulateur

/var/lib/aura/
├── state.json              version installée, dernier profil, historique MAJ
├── updates/                téléchargements en cours (reprise possible)
├── prefixes/               préfixes Wine/Proton sandboxés par jeu
└── games/                  point de montage par défaut des bibliothèques

/opt/AuraOS/
├── proton/                 versions Proton-GE épinglables par jeu
└── emulators/              RetroArch, Dolphin, PCSX2, RPCS3…
```

## 5. Chaîne de boot

```
UEFI → shim (Secure Boot optionnel) → GRUB (menu A/B + Windows)
  → linux + initramfs (zram activé tôt)
  → systemd (targets : aura-gaming.target / aura-desktop.target)
  → greetd : auto-login « gamer » sur session aura-shell
  → gamescope + Aura Shell → UI Gaming (prête en ≤ 15 s)
```

- `aura-gaming.target` : greffe gamescope + Aura Shell, gèle le superflu.
- `aura-desktop.target` : XFCE ; les deux targets coexistent, la bascule ne coupe pas la session Gaming (suspendue).

## 6. Modèle de sécurité

- L'UI ne tourne **jamais en root** ; toute action système via **polkit** (`aura-settings`).
- Chaque jeu non natif est exécuté dans **bubblewrap** : pas de `$HOME` complet, accès limité à `/var/lib/aura/prefixes/<jeu>` + le dossier du jeu, réseau activé sauf profil contraire.
- Mises à jour : **SHA-256 + signature minisign** vérifiées avant toute écriture ; le slot actif n'est jamais modifié.
- Pas de télémétrie ; les seules sorties réseau sont les appels GitHub Releases (anonymes).

## 7. Structure du dépôt projet (ce dossier)

```
nomos_OS/
├── docs/            spécifications (00 → 05)
├── scripts/         aura-perf-detect · aura-update · aura-run · build-iso.sh
├── systemd/         unités embarquées dans l'image
├── etc/aura/        fichiers de configuration de référence
└── iso/             paramètres du profil archiso « Live & Play »
```

Pipeline CI (GitHub Actions, hors périmètre de ce dossier) : build archiso → tests QEMU
(boot + smoke tests) → signature → publication Release avec `.iso`, `.sha256`, `.zsync`, `.minisig`.
