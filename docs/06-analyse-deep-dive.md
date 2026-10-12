# 06 — Deep-Dive Analysis & Stratégie Produit
**Réf. :** AURA-AUDIT-001 · **Date :** octobre 2026 · **Périmètre :** audit technique + propositions avancées

---

## 0. Positionnement (contexte marché, octobre 2026)

Le paysage s'est structuré : **SteamOS** s'ouvre aux constructeurs tiers (Legion Go S sous licence
officielle, retour du « Steam Machine », support GPU discrets), **Bazzite** impose le modèle
immutable/auto-réparant avec support NVIDIA et 20+ handhelds, **ChimeraOS** tient le créneau
canapé/émulation. Le Linux gaming dépasse les 5 % sur Steam.

**Conséquence stratégique** : être « un SteamOS-like » de plus est un suicide produit. Le créneau
défendable d'AuraOS est triple et aucun concurrent ne le couvre :
1. **Le plancher contractuel 30 FPS sur vieux matériel** (« merguez ») — SteamOS/Bazzite visent
   le hardware moderne ; la machine de récupération de 2012 est un non-sujet chez eux.
2. **L'universalité des launchers** traitée comme une couche système (l'Agenciel), pas comme des
   apps empilées.
3. **L'incassable** : A/B + boot counting + session de secours hors-ligne = « l'OS qui répare sa
   propre casse ».

---

## 1. ANALYSE DES RISQUES & BOTTLENECKS TECHNIQUES

### 🔴 Risque 1 — Le mur Vulkan : la promesse « 30 FPS » entre en collision avec les couches de compatibilité

**Le piège caché.** Le plancher 30 FPS est promis sur des machines « merguez » (2012-2015, IGP),
mais le coût dominant n'est pas l'UI : c'est la **traduction** (DXVK/VKD3D) et le **shader
compilation stutter**. Concrètement :
- DXVK exige **Vulkan 1.3** ; une Intel HD 4000 (2012) n'a pas de Vulkan du tout → la moitié de la
  bibliothèque (jeux Windows) est **injouable quelle que soit l'optimisation système**.
- Sur NVIDIA Kepler (GTX 6xx/7xx), le seul pilote fonctionnel est la **branche legacy 470, en fin
  de vie et retirée par les distributions en 2026** (Ubuntu la retire, Mint bloque ses MAJ, kernels
  récents la cassent) — et elle ne supporte ni GBM ni gamescope en Wayland proprement.
- Le stutter de compilation de shaders au premier lancement fait *percevoir* 15 FPS même quand la
  moyenne est à 30.

**Solutions concrètes.**
1. **Matrice de capacités hardware** (étendre `aura-perf-detect`) : GPU → `{vulkan13, wayland-gbm,
   dxvk, vkd3d}` → à l'affichage, chaque jeu de la bibliothèque est **grisé honnêtement**
   (« non jouable sur cette machine : Vulkan manquant ») au lieu de planter au lancement. Le contrat
   devient : *30 FPS pour tout jeu compatible selon la matrice, jamais moins.*
2. **Deux sessions gaming** : `aura-gaming` (gamescope/Wayland) et `aura-gaming-x11` (fallback :
   X11, compositing coupé) pour les GPU legacy ; sélection automatique au boot avec **rollback de
   session** (principe boot-counting appliqué à la session) si la session plante.
3. **Stratégie shaders** : caches DXVK/VKD3D par jeu, précompilation des pipelines au premier
   lancement (en tâche de fond, hors `game.slice`), partage de caches entre joueurs (opt-in).
4. **Badge « Verified 30 FPS »** par jeu (→ G2/Autotune) : la promesse est tenue *par titre*, pas
   globalement — c'est honnête et marketinglement fort.

### 🔴 Risque 2 — Dual-boot : NTFS, BitLocker et Fast Startup peuvent tuer la réputation du produit

**Le piège caché.** « Dual-boot sans perte de données » est le livrable le plus dangereux :
- **Fast Startup** de Windows laisse NTFS « sale » (hiberfil.sys) → ntfsresize refuse ou pire,
  écrit sur une filesystem hibernée = corruption.
- **BitLocker** (de plus en plus activé par défaut sur Win11) : une partition chiffrée **ne se
  redimensionne pas en sécurité**, period.
- **Intel RST/RAID** : le disque n'est pas vu tel quel par l'installeur.
- **Windows Update** réécrit régulièrement l'ordre de boot EFI → GRUB disparaît aux yeux de
  l'utilisateur (« Linux a cassé mon Windows » — la plainte n°1 des dual-boot).

**Solutions concrètes.**
1. **Gates durs dans l'installeur** : détection du flag d'hibernation et des métadonnées FVE
   (BitLocker) → **refus net du redimensionnement** + parcours guidé (désactiver Fast Startup,
   suspendre BitLocker) ; jamais de « force ».
2. **Chemin recommandé « zéro écriture NTFS »** : guider l'utilisateur pour rétrécir la partition
   *depuis Windows* (gestion des disques), puis AuraOS s'installe dans l'espace libre déjà créé —
   le risque de corruption tombe à ~0.
3. **Ne jamais remplacer le Windows Boot Manager** : GRUB le *chainload*, os-prober en lecture
   seule, sauvegarde GPT + ESP sur la clé USB, restauration auto de l'entrée Windows si
   l'installation est interrompue.
4. **Matrice de tests CI** : VM Win10/11 × {Fast Startup on/off, BitLocker on/off} avant toute
   release.

### 🔴 Risque 3 — Dette de la pile logicielle & overhead du pilotage dynamique

**Le piège caché.**
- Le rootfs A/B = une image complète par release ; plus grave, l'Agenciel épingle **Proton-GE,
  Heroic, les émulateurs** : une matrice de compatibilité qui pourrit chaque semaine (anti-cheats,
  régressions Proton).
- Le game-mode gèle `background.slice` : risque de geler des choses qui comptent (keepalives
  réseau → déconnexions Discord, timers), et sur 2 Go de RAM le **OOM killer peut tuer le jeu**
  malgré le zRAM.
- Les hooks de détection peuvent devenir un overhead s'ils sondent le matériel **au lancement**
  d'un jeu (100-300 ms + I/O) — inacceptable sur la cible 30 FPS.

**Solutions concrètes.**
1. **Image core légère** (< 8 Go) + couche modulaire « Aura Labs » (émulateurs) installable à la
   demande ; versions de Proton épinglées **par jeu** avec manifeste testé en CI (3 jeux de
   référence smoke-testés à chaque release).
2. **Game-mode durci** : ne geler **jamais** `user.slice` (pipewire/audio), ni les cibles réseau ;
   `oom_score_adj` du jeu à -1000 + `MemoryMax` sur les services non vitaux ; profil précalculé au
   boot → `game-start` en **O(1)**, zéro sondage au lancement.
3. **Deltas maîtrisés** : zsync par blocs squashfs (déjà prévu) + test des deltas sur le canal
   beta avant stable.
4. **Observabilité sans télémétrie** : `aura-inspect` local (systemd-analyze blame, frame-times),
   exporté uniquement à la demande de l'utilisateur.

---

## 2. GAME CHANGERS (propositions de fonctionnalités)

### ⭐ G1 — « Aura Vault » : sauvegardes unifiées cross-launchers
Le problème que personne ne résout au niveau système : mes saves sont éclatées entre préfixes
Proton, jeux natifs, émulateurs et launchers. Aura Vault = **registre de chemins de sauvegarde par
jeu** + moteur de synchro agnostique (cible choisie par l'utilisateur : NAS, S3/R2, git — aucune
cloud imposée), résolution de conflits, **time-machine par jeu** (« remonter 3 saves en arrière »),
journal offline-first. Vue « Sauvegardes » dans Aura Shell + badge de synchro par jeu.
*Différenciation : Steam Cloud est cloisonné à Steam ; Ludusavi est une app tierce non intégrée.*

### ⭐ G2 — « Aura Autotune » : tuning automatique par jeu + badge « Verified 30 FPS »
Score hardware (`aura-perf-detect`) × base de presets par jeu : au premier lancement, une passe de
calibration mesure les **1% low FPS** sur 2-3 presets (résolution interne, ombres, AA) et conserve
le meilleur (exploration style bandit). La bibliothèque affiche ensuite **« Verified 30 FPS »**
(merguez) ou **« Verified 144 »** (high-end). Les presets anonymes remontent en opt-in (communauté).
*C'est l'opérationnalisation du plancher 30 FPS : la promesse devient mesurée et visible.*

### ⭐ G3 — « Aura Respawn » : session de secours hors-ligne, l'OS incassable
Une session minimale toujours bootable (entrée dédiée du menu de boot, rendu logiciel) : rollback
du slot A/B, vérification de signature des fichiers cœur, remise à zéro *aveugle* de l'affichage
(safe 720p), réinstallation de la pile graphique — **100 % hors-ligne**. Combinée au boot counting :
« AuraOS répare sa propre casse ». Argument marketing majeur pour la cible machine de récupération.

### ⭐ G4 — « Resume » : reprise instantanée façon console
Le *killer feel* des consoles : à la sortie d'un jeu (ou arrêt de la machine), le processus reste
gelé dans `game.slice` + suspend-to-RAM → « Reprendre la partie » en **< 2 s** depuis le launcher.
v1 = sleep + freezer (déjà 80 % implémenté par le game-mode), v2 = snapshot disque (hibernation).
Sur merguez : snapshot dans le zRAM. *Aucun OS gaming desktop ne propose cela proprement.*

---

## 3. EXPÉRIENCE UTILISATEUR & POLISSAGE (UX/UI)

### 3.1 Fluidité Gaming ↔ Bureau (sans sensation de « changer d'OS »)
- **Design system unique** : tokens JSON → thème Qt6 **et** thème GTK4 générés (même palette,
  typographie, radius) ; même wallpaper, mêmes polices → le Bureau est un « espace » d'AuraOS,
  pas un autre produit.
- **`aura-sessiond`** : état partagé par D-Bus entre les deux modes (réseau, volume, batterie,
  notifications, montages) — couper le Wi-Fi dans XFCE se répercute instantanément dans l'UI Gaming
  et inversement.
- **Continuité visuelle** : à la bascule, un thumbnail live de l'UI Gaming reste dans le dock du
  Bureau ; au retour, on reprend exactement au scroll/sélection (déjà prévu par SIGSTOP — conserver
  aussi la position de navigation).
- **Raccourcis symétriques** : combo manette global (Guide+Y) dans les deux sens, même overlay
  rapide dans les deux modes.
- Sur profil merguez : badge « mode bureau économe » + suspension GPU effective pendant le Bureau.

### 3.2 Notifications en jeu sans casser les 30 FPS
Principe directeur : **l'application ne rend jamais par-dessus le jeu.**
1. **Toasts dessinés par le compositor** (couche gamescope) : coût ≈ 0,1 ms/frame, taille fixe,
   fade simple **sans blur**, budget strict **1 toast / 5 s** maximum.
2. **File d'attente + résumé post-session** : « Pendant votre partie : 1 mise à jour, 2 messages
   Discord » — rien n'interrompt le gameplay.
3. **Focus mode** par défaut à l'activation d'un jeu : muet sauf critiques système (MAJ de
   sécurité, batterie faible). Les apps tierces (Discord) passent par un **pont de notifications
   D-Bus** avec regroupement (« 3 messages · Discord » en un seul toast).
4. **Règle merguez** : zéro toast animé pendant le jeu — simple point d'attention dans l'overlay
   Guide, rendu **à la demande** (coût nul pendant le jeu).
5. **Budget de frame contractuel** : le coût du shell est mesuré en CI (test de régression
   frame-time sur VM) — le budget UI doit rester < 4 ms sur IGP, mesuré et bloquant.

---

## 4. FEUILLE DE ROUTE STRATÉGIQUE (4 phases)

### Phase 1 — PoC « Boot-to-UI » (semaines 1-4) — *sur VM*
- Profil archiso minimal → **ISO bootable dans QEMU** : boot → stub Aura Shell ≤ 15 s, session
  gamescope, `aura-perf-detect` et `aura-update` testés contre un dépôt GitHub de test.
- **Livrables** : ISO VM, suite de tests automatisés (bash), matrice de capacités hardware v0.
- **Critères de sortie** : boot + vérification MAJ OK sur 3 VM (2 vCPU/2 Go → `merguez`,
  4 vCPU/8 Go → `mid`, 8 vCPU/16 Go → `high`).

### Phase 2 — Tranche verticale « Jouable » (semaines 5-10) — *sur matériel réel*
- Agenciel v1 (routing Proton-GE + bubblewrap), game-mode de bout en bout, installeur dual-boot
  avec gates BitLocker/Fast Startup. Tests sur **2 machines réelles** (1 merguez, 1 high-end).
- **Critères de sortie** : 3 jeux à **≥ 30 FPS (1% low)** sur la machine merguez, **144 FPS**
  débridés sur high-end ; 0 perte de données sur 10 installations dual-boot consécutives.

### Phase 3 — Bêta fermée « Complète » (semaines 11-18)
- Aura Shell complet (bibliothèque, overlay, MAJ 1-clic), Autotune v1, Respawn, CI signée
  (minisign), **20 bêta-testeurs** sur matériels volontairement hétérogènes (dont Kepler/X11).
- **Critères de sortie** : sessions sans crash > 95 %, MAJ A/B + rollback validés en conditions
  réelles, budget frame UI < 4 ms sur IGP mesuré.

### Phase 4 — Release publique v1.0 (semaines 19-24)
- Durcissement sécurité (audit sandbox), documentation + site, playbook de support, **release
  signée sur GitHub**, campagne « 30 FPS vérifiés · l'OS incassable ».
- **Critères de sortie** : v1.0.0 publiée avec canaux stable/beta, tableau de compatibilité par
  jeu public, promesse 30 FPS vérifiable (badges Autotune).

### Par quoi commencer concrètement, demain matin
1. Le **profil archiso + smoke tests QEMU** (Phase 1) — c'est le goulot de tout le reste.
2. La **matrice de capacités GPU** (extension d'`aura-perf-detect`) — elle débloque l'honnêteté de
   la bibliothèque et le fallback X11.
3. Les **gates dual-boot** (BitLocker/Fast Startup) — avant même la bêta publique, c'est le
   risque réputationnel n°1.
