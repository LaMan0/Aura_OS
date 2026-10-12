# 04 — Agenciel : compatibilité universelle des jeux

## 1. Rôle

L'**Agenciel** est la couche d'abstraction qui permet de lancer *n'importe quel jeu*
depuis un point d'entrée unique : l'écran Bibliothèque d'Aura Shell. Il repose sur
le script [`scripts/aura-run`](../scripts/aura-run) + la table de routage ci-dessous.

## 2. Table de routage automatique

| Entrée détectée | Couche activée | Composants |
|---|---|---|
| ELF natif (Linux) | exécution directe | gamescope (enveloppe graphique) |
| `.exe` / `.msi` | **Proton-GE** | Wine + DXVK (Dx9-11) + VKD3D-Proton (Dx12) |
| `.exe` via Steam | Steam / Proton épinglé par le jeu | `steam://run/<appid>` |
| Epic Games / GOG | Heroic Launcher (mode headless) | `heroic launch <game-id>` |
| `.sh`, `.AppImage` | sandbox **bubblewrap** | isolation stricte du système de fichiers |
| ROM (nes, gba, ps2, iso…) | émulateur dédié | table `/usr/share/aura/emulators/map` |
| `steam://` | client Steam | ouverture URI |

Détection en 3 temps (dans `aura-run`) :
1. **URI** (`steam://`) → client Steam ;
2. **extension** → table de routage ;
3. **signature binaire** (`file`, magie ELF `\x7fELF`) → natif sinon sandbox.

## 3. Conteneurisation par jeu

Chaque jeu non natif reçoit un **préfixe isolé** :

```
/var/lib/aura/prefixes/<nom-du-jeu>/
├── pfx/          préfixe Wine/Proton (registre, C:, DLL)
├── compatdata/   données Steam compat
└── profile.conf  réglages épinglés du jeu (version Proton, variables DXVK…)
```

- Exécution sous **bubblewrap** : pas d'accès au reste de `$HOME`, `/etc` en lecture seule,
  réseau autorisé (sauf profil « hors-ligne »), processus tué avec le parent (`--die-with-parent`).
- Variables par défaut : `DXVK_ASYNC=1`, `VKD3D_CONFIG=dxr12`, `WINE_FULLSCREEN_FSR=1`
  (l'upscaling FSR est l'allié du plancher 30 FPS sur merguez).

## 4. Profils de compatibilité par jeu

Un clic sur « Détails » dans Aura Shell expose les réglages mémorisés :

```
[version Proton]  [résolution interne]  [FPS cap]  [DXVK async]  [sandbox réseau]  [préfixe]
   proton-ge        dynamic:0.50-1.00       30          on             off         dédié
```

Ces réglages sont stockés dans `profile.conf` et relus par `aura-run` au lancement ;
le **game-mode** (`aura-perf-detect game-start`) s'applique automatiquement autour du processus.

## 5. Émulateurs

`/usr/share/aura/emulators/map` (extension → système → commande) :

```
nes=nes            → retroarch -L fceumm
gba=gba            → retroarch -L mgba
ps2=ps2            → pcsx2-qt
ps3=ps3            → rpcs3
wii=wii            → dolphin-emu
n64=n64            → retroarch -L mupen64plus_next
iso=psx            → retroarch -L beetle_psx_hw
```

## 6. Limites connues (à documenter dans l'UI)

- **Anti-cheats noyau** (EAC/BattlEye) : non supportés hors mode natif Proton validé par l'éditeur.
- **Jeux Store UWP/MSIX** : non supportés (hors périmètre Wine).
- **Mods Windows** : fonctionnent dans le préfixe du jeu, avec l'arborescence `C:` du préfixe.
- Certains lanceurs (Battle.net, EA App) : pris en charge via Heroic/Lutris, installation manuelle.

## 7. Critères d'acceptation Agenciel

- [ ] Un `.exe` inconnu se lance via Proton-GE sans action de l'utilisateur autre que « Jouer ».
- [ ] Un ELF natif ne passe jamais par Wine.
- [ ] Deux jeux distincts n'écrivent jamais dans le même préfixe.
- [ ] Un jeu en fonctionnement est dans `game.slice` (vérifiable via `/sys/fs/cgroup/game.slice/cgroup.procs`).
