# AuraOS — Système d'exploitation gaming haute performance

**Version du cahier des charges :** 1.0 — projet `nomos_OS`
**Rôle :** conception technique complète (architecture, UI, mise à jour, performances) + scripts de déploiement.

AuraOS est une distribution Linux hybride modulaire optimisée pour le jeu vidéo :
un mode Gaming « chic & épure » au boot, un mode Bureau XFCE d'un raccourci,
une couche de compatibilité universelle (Steam/Proton, Epic, GOG, `.exe` isolés, émulateurs),
une mise à jour 1-clic depuis GitHub Releases, et un profiler matériel garantissant
**30 FPS minimum sur machine modeste ("merguez")** et **144+ FPS sans bridage sur high-end**.

---

## Arborescence du dépôt

```
nomos_OS/
├── README.md                        ← ce fichier
├── docs/
│   ├── 00-cahier-des-charges.md     ← spécification fonctionnelle & technique complète
│   ├── 01-architecture-globale.md   ← distro socle, couches, partitionnement, structure /etc /usr /var
│   ├── 02-spec-interface-ui.md      ← Mode Gaming + Mode Bureau + bascule instantanée
│   ├── 03-systeme-mise-a-jour.md    ← pipeline GitHub Releases, A/B rootfs, 1-clic
│   ├── 04-agenciel-compatibilite.md ← abstraction multi-plateformes (Proton/Wine/DXVK/sandbox)
│   └── 05-installation-live-usb.md  ← ISO hybride, installeur 3 étapes, dual-boot sécurisé
├── scripts/
│   ├── aura-perf-detect             ← PROFILER MATÉRIEL (livrable clé) — 30 FPS ↔ 144+ FPS
│   ├── aura-update                  ← client de mise à jour GitHub (vérif/télécharge/vérifie/applique)
│   ├── aura-run                     ← lanceur de jeu universel (détection d'exécutable + game-mode)
│   ├── aura-vault                   ← sauvegardes cross-launchers (registre, time-machine, synchro)
│   ├── bench-fps.sh                 ← benchmarks : 1% low FPS & validation du plancher 30 FPS
│   └── build-iso.sh                 ← build d'ISO hybride + release GitHub
├── systemd/
│   ├── aura-perf-detect.service     ← application du profil perf au démarrage
│   ├── aura-update.service          ← unité de mise à jour (oneshot)
│   └── aura-update.timer            ← vérification périodique des releases GitHub
├── etc/aura/
│   ├── aura.conf                    ← configuration système de référence
│   └── update.conf                  ← dépôt GitHub, clés de signature, canal (stable/beta)
├── iso/
│   └── README-iso.md                ← profil archiso / paramètres de l'image Live & Play
├── bench/traces/                    ← traces de référence du gate 30 FPS (CI)
└── .github/workflows/bench-gate.yml ← CI : self-tests + gate 30 FPS, bloque la release
```

## Démarrage rapide (sur une machine Linux / VM de build)

```bash
# 1. Valider la syntaxe des scripts
bash -n scripts/aura-perf-detect scripts/aura-update scripts/aura-run scripts/build-iso.sh

# 2. Détecter le matériel et simuler l'application du profil (sans root)
sudo scripts/aura-perf-detect detect
sudo scripts/aura-perf-detect apply --dry-run

# 3. Appliquer le profil de performance (root)
sudo scripts/aura-perf-detect apply

# 4. Vérifier les mises à jour depuis GitHub
sudo scripts/aura-update check
sudo scripts/aura-update apply --reboot

# 5. Lancer un jeu via la couche de compatibilité
scripts/aura-run --profile default ~/Games/mon_jeu.exe

# 6. Construire l'ISO hybride (nécessite archiso)
sudo scripts/build-iso.sh --version 1.0.0

# 7. Benchmarks : valider le plancher 30 FPS (1% low) par jeu
scripts/bench-fps.sh self-test                    # vérifie le moteur statistique
scripts/bench-fps.sh analyse --input trace.csv --game "Mon Jeu" --floor 30 --mark-verified
scripts/bench-fps.sh report                       # badges "Verified 30 FPS"
```

## Décisions d'architecture (résumé)

| Domaine | Choix retenu | Justification |
|---|---|---|
| Distro socle | **Arch Linux minimal + archiso** | Rolling release (Mesa/Proton récents), outil ISO officiel, philosophie proche de SteamOS 3 |
| Boot / init | **systemd** (UEFI + BIOS, GRUB ou Limine) | cgroups v2 natif (indispensable au game-mode), slicing, boot counting |
| Compositor Gaming | **gamescope** (Wayland) | bas résolution interne dynamique, VRR, FSR, isolation du flux graphique |
| UI Gaming | **Aura Shell (Qt6 Quick / QML)** | rendu GPU, transitions fluides, mode "effets coupés" sur merguez |
| Bureau | **XFCE ultra-customisé** (+ Openbox optionnel) | < 300 Mo RAM, mature, pilotable sans GPU récent |
| Compatibilité jeux | **Proton-GE + Wine + DXVK/VKD3D-Proton**, sandbox **bubblewrap** | couche unique, préfixes isolés par jeu |
| Mises à jour | **GitHub Releases + zsync (delta) + minisign** + rootfs A/B | 1-clic, rollback automatique, bande passante minimale |
| Performances | **aura-perf-detect** (profils merguez/mid/high + game-mode) | plancher strict 30 FPS, débridage total 144+ Hz |

## Exigences de performance contractuelles

- **Merguez** (2–4 Go RAM, IGP, vieux CPU) : plancher **30 FPS** soutenu en 720p interne dynamique, UI sans effet, empreinte RAM idle ≤ 800 Mo.
- **Mid-range** : 60 FPS cap natif, effets UI partiels.
- **High-end** : **aucun bridage**, taux de rafraîchissement écran natif (144/165/240 Hz+), VRR, cœurs alloués au jeu via cgroups v2.
- Bascule jeu en **&lt; 2 s** vers le mode performance, retour au repos **&lt; 3 s** après la fin du jeu.

Voir [docs/00-cahier-des-charges.md](docs/00-cahier-des-charges.md) pour la spécification complète.
