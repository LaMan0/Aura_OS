# 02 — Spécification de l'interface utilisateur (double mode)

## 1. Principes directeurs

1. **Le jeu d'abord** : l'UI n'est pas un bureau déguisé, c'est un launcher-console.
2. **Manette-first** : toute action atteignable sans souris ; clavier/souris en complément transparent.
3. **Chic & épure** : typographie unique, palette sombre profonde, espaces négatifs généreux, **zéro widget parasite**.
4. **Budget frame** : le compositor garde 1 frame d'avance ; le coeur UI se dessine en ≤ 4 ms sur IGP (profil merguez).

## 2. Mode Gaming « Chic & Épuré » (par défaut au boot)

### 2.1 Structure — une seule surface, quatre destinations

```
┌──────────────────────────────────────────────────────────────────┐
│  AURA                                    ⚡ profil  🎮 en jeu    │ ← barre d'état (1 ligne)
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│        ◀   [  JEUX RÉCENTS  — carrousel plein cadre  ]   ▶      │
│                                                                  │
│            artwork plein écran · titre · FPS estimés              │
│                                                                  │
│   [ JOUER ]      [ DÉTAILS ]      [ AJOUTER UN JEU ]            │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│   🎮 Bibliothèque      ⭐ Favoris      ⚙ Système      💻 Bureau │ ← barre basse
└──────────────────────────────────────────────────────────────────┘
```

- **Écran Accueil** : carrousel horizontal (2 max visibles + teasers), démarrage sur le dernier jeu joué.
- **Bibliothèque** : grille 6×N filtrable (source : Steam / Epic / GOG / Fichiers / Émulateurs), tri intelligent, recherche instantanée (manette : pavé visuel).
- **Détails du jeu** : artwork, métadonnées, **profil de compatibilité** (version de Proton, résolution interne, FPS cap) modifiable en 3 boutons.
- **Système** : mises à jour (voir §4), réseau, son, écran (taux de rafraîchissement détecté), stockage, à-propos.
- **Bureau** : raccourci de bascule (§3).

### 2.2 Navigation manette (cartographie SDL)

| Entrée | Action |
|---|---|
| Stick / D-pad | déplacement de focus |
| A (Cross) | valider |
| B (Circle) | retour |
| X / Y | actions contextuelles (favoris, options) |
| LB / RB | changer d'onglet / défiler le carrousel |
| Start | overlay rapide (volume, FPS cap, capture, quitter le jeu) |
| Guide (bouton Home) | retour immédiat à l'Accueil (depuis le jeu : overlay) |

### 2.3 Langage visuel (tokens)

| Token | Valeur | Usage |
|---|---|---|
| `bg.base` | `#0B0D12` | fond global (noir bleuté profond) |
| `bg.elevated` | `#141926` | cartes, panneaux |
| `accent.aura` | `#6EE7F9` → `#A78BFA` | dégradé signature (focus, CTA) |
| `text.primary` | `#F4F6FB` | titres |
| `text.muted` | `#9AA3B8` | métadonnées |
| `radius.card` | `20 px` | cartes, boutons |
| `motion.fast` | `140 ms ease-out` | focus, hover |
| `motion.page` | `260 ms cubic-bezier(.2,.8,.2,1)` | transitions de vue |
| Police | Inter / JetBrains Mono (chiffres FPS) | hiérarchie 16/20/28/44 |

**Règle « merguez » :** `motion.page` passe à `0 ms`, les flous (`blur`) et ombres sont remplacés par des aplats ; l'identité visuelle reste (palette, typographie, espacement) mais le coût GPU tombe sous 1 ms/frame.

### 2.4 Architecture technique de l'UI

- **Aura Shell** : application **Qt6 Quick (QML)** unique, tournant dans **gamescope** (Wayland).
- QML séparé en `Theme` (tokens), `ViewModels` (C++ : bibliothèque, jeux, système), `Views`.
- La bibliothèque de jeux est indexée par un daemon léger (`aura-libraryd`) qui agrège Steam (`appmanifest_*`), Heroic (Epic/GOG), les fichiers `.exe` déclarés et les ROMs.
- Le taux de rafraîchissement UI suit **le taux de l'écran** (144 Hz → UI à 144 Hz, animations `FrameAnimation` cadencées vsync).

## 3. Mode Bureau classique & bascule instantanée

### 3.1 Composition

- **XFCE ultra-customisé** (xfwm4, thème Aura : mêmes tokens `bg.base` / `accent.aura`), panel unique 44 px, dock latéral optionnel.
- Applications : Firefox/Librewolf (préconfiguré : `gfx.webrender.all`, VA-API activé, onglets suspendus), LibreOffice, Thunar, GIMP/Blender optionnels.
- Panneau **Aura Settings** (partagé avec le mode Gaming) : même code Qt6 embarqué dans XFCE.

### 3.2 Mécanisme de bascule (≤ 3 s)

```
Mode Gaming (gamescope + aura-shell)
   ── clic « Bureau » / combo manette (Guide+Y) ──▶
       1. aura-shell passe en état suspendu (SIGSTOP du processus UI)
       2. xfce4-session démarre côté X11/Wayland secondaire
       ── retour : SIGCONT + remise au premier plan ──
Mode Bureau (XFCE) — l'état du launcher (scroll, sélection) est conservé
```

- Les deux sessions coexistent dans systemd (`aura-gaming.service`, `aura-desktop.service`) : **aucune fermeture d'application**, aucun rechargement de la bibliothèque au retour.
- Sur profil **merguez**, la session Gaming est suspendue (pas seulement cachée) pour libérer RAM et GPU pendant le mode Bureau.

### 3.3 Overlay rapide (depuis un jeu)

Bouton Guide → overlay translucide 40 % (fond `bg.base` @ 0.6) : quitter le jeu, basculer Bureau, régler FPS cap / résolution interne, notifications MAJ, capture.

## 4. Intégration des mises à jour dans l'UI

- **Badge** sur l'onglet Système dès qu'une release plus récente est détectée (`aura-update check` → `state.json`).
- Carte « Mise à jour disponible : v1.2.0 (delta 210 Mo) » avec bouton unique **[ Mettre à jour ]** :
  barre de progression → vérification signature → « redémarrage dans 10 s (annuler) ».
- Le reste (téléchargement en arrière-plan, application sur slot B) est piloté par `aura-update.service`, l'UI ne fait qu'observer l'état via `state.json` + notifications D-Bus.

## 5. Accessibilité & contraintes

- Cibles tactiles ≥ 48 px, focus clavier visible (halo `accent.aura`), contraste AA minimum sur `text.primary`.
- Tailles de police dynamiques (100 % / 125 % / 150 %) — recalcul sans redémarrage.
- Mode « lecture écran » léger (Qt Accessibility) sur les vues principales ; sous-titres forcés dans l'overlay jeu.
- Toute action critique (effacer un jeu, réinitialiser) exige une confirmation double, jamais un simple appui.

## 6. Critères d'acceptation UI

- [ ] Boot → Accueil jouable à la manette en ≤ 15 s (SSD) sans jamais montrer un terminal.
- [ ] Navigation complète sans souris ; aucune animation > 16 ms sur IGP (profil merguez).
- [ ] Bascule Gaming ↔ Bureau ≤ 3 s avec conservation de l'état.
- [ ] La carte MAJ apparaît automatiquement ≤ 10 min après publication d'une release.
- [ ] Le taux de l'UI suit le taux de l'écran : 60 Hz capé sur merguez, 144+ Hz libre sur high.
