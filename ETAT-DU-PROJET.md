# ETAT-DU-PROJET.md — AuraOS : synthèse complète
**Date :** 12 octobre 2026 · **Projet :** `nomos_OS` (C:\Users\maeno\Documents\nomos_OS)
**Objet :** tout ce qui a été fait, ce qu'il reste à faire, les problèmes potentiels, et l'inventaire complet des fichiers.

---

## 1. CE QUI A ÉTÉ FAIT

### 1.1 Conception documentaire (6 spécifications + README)
| # | Livrable | Contenu |
|---|---|---|
| 1 | `docs/00-cahier-des-charges.md` | Spéc fonctionnelle & technique complète : FR-UI-01→05, FR-JV-01→04, FR-INS-01→05, FR-MAJ-01→05, FR-PERF-01→05, exigences NFR (boot ≤ 15 s, RAM idle ≤ 800 Mo merguez…), contraintes, critères d'acceptation, glossaire, jalons M1-M6 |
| 2 | `docs/01-architecture-globale.md` | Choix du socle (**Arch Linux + archiso**, comparatif vs Debian), pile en couches, partitionnement GPT avec **rootfs A/B**, arborescence /etc/aura /usr/lib/aura /var/lib/aura, chaîne de boot, modèle de sécurité |
| 3 | `docs/02-spec-interface-ui.md` | Mode Gaming « chic & épuré » (vues, cartographie manette, tokens visuels `#0B0D12`/`#6EE7F9→#A78BFA`, budget frame ≤ 4 ms), mode Bureau XFCE, bascule ≤ 3 s par suspension, intégration MAJ 1-clic |
| 4 | `docs/03-systeme-mise-a-jour.md` | Pipeline GitHub Releases : timer 6 h → API (ETag) → delta zsync → SHA-256 + minisign → slot inactif A/B → boot counting (rollback auto), machine à états, sécurité de la chaîne |
| 5 | `docs/04-agenciel-compatibilite.md` | Table de routage des jeux (ELF→natif, .exe→Proton-GE/DXVK/VKD3D, ROM→émulateurs, .sh/.AppImage→bubblewrap), préfixes isolés par jeu, limites connues (anti-cheats noyau…) |
| 6 | `docs/05-installation-live-usb.md` | ISO hybride Live & Play (UEFI+BIOS), installeur 3 étapes, dual-boot sécurisé (sauvegarde GPT, redimensionnement non destructif), tableau de dépannage |
| 7 | `docs/06-analyse-deep-dive.md` | Audit stratégique : 3 risques majeurs + solutions, 4 game changers (Aura Vault, Autotune, Respawn, Resume), UX (notifications en jeu), roadmap 4 phases (S1→S24) |

### 1.2 Scripts système (4, en Bash, validés)
| Script | Rôle | État |
|---|---|---|
| `scripts/aura-perf-detect` (~23 Ko) | **Profilage matériel dynamique** : détection CPU/RAM/GPU/stockage/écran → score 0-11 → profil `merguez`/`mid`/`high` ; applique zRAM, governor, I/O, sysctls, MGLRU, préférences UI ; **game-mode** (governor performance, `game.slice`, gel `background.slice`, ionice, GPU max) | ✅ testé |
| `scripts/aura-update` (~13 Ko) | **Client MAJ GitHub** : check (ETag, sémantique), download (delta zsync, reprise), apply (SHA-256 + minisign, slot A/B, bootloader), rollback, status | ✅ testé |
| `scripts/aura-run` (~8 Ko) | **Lanceur universel (Agenciel)** : routage par extension/signature, Proton-GE + sandbox bwrap, enveloppe gamescope, game-mode automatique | ✅ testé |
| `scripts/build-iso.sh` (~7 Ko) | **Build d'ISO hybride** archiso + signature minisign + zsync + publication GitHub Release | ✅ testé (dry-run) |
| `scripts/bench-fps.sh` (~11 Ko) | **Suite de benchmarks** : 1% low / 0.1% low / P1 / stutters par jeu, validation du plancher (30 FPS merguez), registre + badges « Verified 30 FPS » | ✅ testé (self-test + PASS/FAIL) |
| `scripts/aura-vault` (~13 Ko) | **Aura Vault** : registre de saves cross-launchers (Proton/natif/émulateurs), time-machine par jeu, synchro vers cible choisie (local/NAS/rsync/rclone), restauration, journal | ✅ testé (self-test bout en bout) |

### 1.3 Configuration & intégration
- `systemd/` : `aura-perf-detect.service` (profil au boot), `aura-update.service` (oneshot), `aura-update.timer` (6 h + jitter).
- `etc/aura/` : `aura.conf` (profils, UI, chemins), `update.conf` (dépôt GitHub, canal, clé minisign, bande passante).
- `iso/README-iso.md` : structure attendue du profil archiso (`profiledef.sh`, `packages.x86_64`, `airootfs/`).

### 1.4 Preview interactive de l'interface (en local)
- `preview/index.html` (~32 Ko) : maquette fonctionnelle fidèle aux tokens de la spec UI — mode Gaming (carrousel, bibliothèque, système), overlay game-mode avec FPS-mètre, carte MAJ 1-clic simulée, bascule vers le mode Bureau XFCE (Thunar, dock), **bascule de profil merguez/mid/high en direct** (coupe réellement animations/blur en merguez).
- Servie sur `http://127.0.0.1:8231` (serveur Python), affichée dans l'onglet Preview.

### 1.5 Commandes exécutées (reproductibles)
```bash
# Structure
mkdir -p ~/Documents/nomos_OS/{docs,scripts,systemd,etc/aura,iso,preview}

# Validation syntaxe (tous OK)
bash -n scripts/aura-perf-detect scripts/aura-update scripts/aura-run scripts/build-iso.sh

# Tests de fumée (exécutés, tous verts)
bash scripts/aura-perf-detect detect                    # → score matériel + profil
bash scripts/aura-perf-detect apply --profile merguez --dry-run   # → liste les actions, exit 0
bash scripts/aura-perf-detect status | game-start --dry-run | game-end --dry-run
bash scripts/aura-run --dry-run /tmp/demo_jeu.exe       # → "DRY-RUN → proton"
bash scripts/aura-update --help | status                # → exit 0, état lisible
bash scripts/build-iso.sh --version 1.0.0 --dry-run     # → plan de build, exit 0
bash scripts/build-iso.sh --version abc                 # → refus, exit 20

# Preview locale
python -m http.server 8231 --bind 127.0.0.1 --directory ~/Documents/nomos_OS/preview
```

### 1.6 Bugs réels détectés et corrigés (puis re-testés)
1. **Comparaisons arithmétiques bash** `(( PROFILE == "merguez" ))` toujours vraies (les deux côtés s'effondrent à 0) → remplacées par `[[ ... ]]`.
2. **Pièges `set -e`** : fonctions se terminant par une liste `&&` retournant 1 → le script mourait silencieusement (`read_perf_conf`, `detect_display`) → `return 0` explicites.
3. **`exec 9>file 2>/dev/null`** redirigeait les erreurs de *tout* le script (messages `die` invisibles) + `flock` manquant → redirection bornée `{ exec ...; } 2>/dev/null` et verrou dégradé proprement.
4. **`$@` dupliqué** dans `launch_native` (l'exécutable était passé deux fois) + `wrap_gamescope` sans effet → tableau `WRAP` global.
5. **Preview** : bloc `@media` placé avant les règles de base → fenêtre du Bureau écrasée à 2 px → bloc déplacé en fin de feuille (mesures DOM avant/après : 2 px → 358 px).

---

## 2. CE QU'IL FAUDRAIT FAIRE

### Priorité 1 — Débloquer la Phase 1 (PoC bootable)
- [ ] **Générer le profil archiso complet** (`iso/aura-profile/profiledef.sh`, `packages.x86_64`, `airootfs/`) décrit dans `iso/README-iso.md` → `build-iso.sh` produit alors une vraie ISO.
- [ ] **Smoke tests QEMU** : boot UEFI + BIOS de l'ISO, mesure du temps de boot, vérification des 3 profils sur VM 2/4/8 vCPU.
- [ ] **Repo GitHub de test** + clé minisign de test → valider `aura-update check/download/apply` de bout en bout (aujourd'hui seul `check/status` est exercé).

### Priorité 2 — Honnêteté du contrat 30 FPS
- [ ] **Matrice de capacités GPU** dans `aura-perf-detect` (Vulkan 1.3, GBM/gamescope, X11 fallback) + grisage honnête des jeux incompatibles dans la bibliothèque.
- [x] **Suite de benchmarks** (`scripts/bench-fps.sh`) : 1% low FPS par jeu, validation du plancher — moteur statistique prouvé par self-test ; restent les mesures sur machine merguez réelle.
- [ ] Session de secours **Aura Respawn** (rollback + remise à zéro affichage hors-ligne).

### Priorité 3 — Sécurité & produit
- [ ] **Gates dual-boot** : détection BitLocker (FVE) et Fast Startup (hiberfil) → refus net + parcours guidé dans l'installeur.
- [ ] Aura Shell en Qt6/QML (aujourd'hui : maquette HTML) + daemon `aura-sessiond` (état partagé Gaming↔Bureau).
- [x] **Pipeline CI bench-gate** (`.github/workflows/bench-gate.yml`) : self-tests + gate 30 FPS par trace de référence, **release bloquée si plancher cassé** — démontré (PASS 32.06 / FAIL 12.50).
- [ ] Compléter la CI : build ISO → tests QEMU → signature → release (dépend du profil archiso).

### Dette technique immédiate
- [ ] **Relancer shellcheck** sur les 4 scripts depuis une machine Linux (indisponible sur l'hôte Windows de rédaction).
- [ ] Tester `aura-perf-detect apply`, `game-start`/`game-end` **en root sur un vrai noyau Linux** (zRAM, cgroups v2, governors non exerçables sous Git Bash).
- [ ] Intégrer les unités systemd dans l'arbre `airootfs` lors du build (déjà prévu dans `build-iso.sh`, à valider).

---

## 3. PROBLÈMES POTENTIELS

### 🔴 Risques majeurs (détaillés dans `docs/06`)
1. **Le mur Vulkan** : DXVK exige Vulkan 1.3 → sur IGP Intel HD 4000 (2012), les jeux Windows sont *injouables* quelle que soit l'optimisation. NVIDIA Kepler (pilote legacy 470) est **retiré par les distros en 2026** et ne supporte pas gamescope/Wayland. → matrice de capacités + fallback X11 + caches de shaders.
2. **Dual-boot** : Fast Startup (NTFS sale), BitLocker (redimensionnement impossible en sécurité), réécriture EFI par Windows Update → gates durs, chemin « rétrécir sous Windows », GRUB chainload sans remplacer le boot Windows.
3. **Dette de pile** : Proton-GE/Heroic/émulateurs = matrice qui pourrit chaque semaine ; gel de `background.slice` (risque réseau/audio) ; OOM sur 2 Go de RAM ; overhead si sondage au lancement de jeu → `game-start` O(1), `oom_score_adj`, image core < 8 Go + couche modulaire.

### 🟡 Limites connues de l'état actuel
| Limite | Impact | Parade |
|---|---|---|
| shellcheck non exécuté (absent de l'hôte Windows) | bugs stylistiques possibles | relancer sous Linux avant Phase 2 |
| Scripts testés sous Git Bash, pas en root sur Linux | comportement réel zRAM/cgroups/governor inconnu | tests en VM Arch (Phase 1) |
| `build-iso.sh` attend `iso/aura-profile/` (non généré) | pas d'ISO réelle aujourd'hui | Priorité 1 ci-dessus |
| `aura-update` testé sur `--help`/`status` uniquement | chemins download/apply non exercés | repo GitHub de test |
| Preview = maquette HTML, pas l'OS | l'UX réelle (latences, frame-time) non mesurée | budget frame bloquant en CI |
| Estimations de roadmap (S1-S24) | charges non calibrées sur vos ressources | ajuster après Phase 1 |

### 🟢 Risques de produit (marché)
- Concurrents bien installés (SteamOS tiers, Bazzite, ChimeraOS) → ne pas jouer « SteamOS-like » mais miser sur les 3 différenciateurs : plancher 30 FPS, universalité launchers, « l'incassable ».
- Promesse marketing « 30 FPS garantis » : ne la publier **que** par badge de jeu vérifié (Autotune), jamais globalement.

---

## 4. RÉSUMÉ COMPLET DES FICHIERS PRÉSENTS

**28 fichiers · 220 Ko** · racine : `C:\Users\maeno\Documents\nomos_OS\`

| Fichier | Taille | Rôle |
|---|---|---|
| `README.md` | 5 Ko | Présentation du projet, arborescence, démarrage rapide, tableau des décisions d'architecture |
| `docs/00-cahier-des-charges.md` | 8 Ko | Spécification fonctionnelle & technique complète (exigences FR/NFR, critères d'acceptation) |
| `docs/01-architecture-globale.md` | 9 Ko | Socle Arch + archiso, couches, partitionnement A/B, arborescence système, sécurité |
| `docs/02-spec-interface-ui.md` | 8 Ko | UI double mode : Aura Shell (gaming) + XFCE (bureau), tokens visuels, bascule |
| `docs/03-systeme-mise-a-jour.md` | 8 Ko | Pipeline MAJ GitHub (delta zsync, minisign, rootfs A/B, rollback) |
| `docs/04-agenciel-compatibilite.md` | 4 Ko | Compatibilité universelle des jeux : table de routage, sandbox, limites |
| `docs/05-installation-live-usb.md` | 4 Ko | ISO Live & Play, installeur 3 étapes, dual-boot sécurisé, dépannage |
| `docs/06-analyse-deep-dive.md` | 13 Ko | Audit : risques, game changers, UX, roadmap 4 phases ← **analyse stratégique** |
| `scripts/aura-perf-detect` | 23 Ko | **Profiler matériel** (merguez/mid/high) + game-mode bas niveau ← **livrable clé** |
| `scripts/aura-update` | 13 Ko | Client de mise à jour GitHub (check/download/apply/rollback/status) |
| `scripts/aura-run` | 8 Ko | Lanceur universel de jeux (routing Proton/natif/émulateur/sandbox) |
| `scripts/build-iso.sh` | 7 Ko | Build d'ISO hybride + signature + publication Release GitHub |
| `scripts/bench-fps.sh` | 11 Ko | Benchmarks : 1% low FPS, validation plancher 30 FPS, badges « Verified 30 FPS » |
| `scripts/aura-vault` | 13 Ko | Aura Vault : saves cross-launchers, time-machine, synchro, restauration |
| `systemd/aura-perf-detect.service` | < 1 Ko | Application du profil perf au boot (oneshot) |
| `systemd/aura-update.service` | < 1 Ko | Vérification MAJ (oneshot, exit 10 = MAJ disponible) |
| `systemd/aura-update.timer` | < 1 Ko | Vérification périodique (6 h, jitter 30 min) |
| `etc/aura/aura.conf` | 2 Ko | Configuration système de référence (profils, UI, chemins) |
| `etc/aura/update.conf` | 1 Ko | Config MAJ (dépôt GitHub, canal stable/beta, clé minisign) |
| `iso/README-iso.md` | 2 Ko | Structure du profil archiso à générer pour `build-iso.sh` |
| `preview/index.html` | 32 Ko | **Preview interactive de l'UI AuraOS** (gaming + bureau + profils + MAJ) |
| `ETAT-DU-PROJET.md` | ~11 Ko | **Ce document** : bilan, reste à faire, problèmes potentiels, inventaire |
| `.github/workflows/bench-gate.yml` | 3 Ko | **CI** : gate 30 FPS (1% low) par trace, bloque la release si cassé |
| `bench/traces/README.md` | 1 Ko | Traces de référence : format, enregistrement MangoHud, test du gate |
| `bench/traces/reference-merguez-30fps.csv` | 12 Ko | Trace de référence (gate) : 1% low = 32.06 FPS ✅ |
| `bench/traces/examples/example-stutter-fail.csv` | 12 Ko | Exemple volontairement raté (hors gate) : 1% low = 12.50 ❌ |
| `.gitignore` | < 1 Ko | Exclusions git (build/, ISO, logs) |
| `.gitattributes` | < 1 Ko | Normalisation LF (les scripts CRLF cassent sous Linux) |

### Comment naviguer dans le projet
1. **Comprendre le projet** : `README.md` → `docs/00` (exigences) → `docs/01` (architecture).
2. **Décider** : `docs/06-analyse-deep-dive.md` (risques, priorités, roadmap).
3. **Exécuter** : `scripts/` (voir §1.5 pour les commandes), `preview/index.html` pour l'interface.
4. **Construire la suite** : `iso/README-iso.md` (Prochaine étape : profil archiso + QEMU).

---
*Document généré le 12 octobre 2026 — mis à jour à chaque étape du projet.*
