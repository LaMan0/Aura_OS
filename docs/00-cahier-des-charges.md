# AuraOS — Cahier des charges technique
**Réf. :** AURA-CDC-001 · **Version :** 1.0 · **Statut :** spécification validée pour implémentation

---

## 1. Contexte & vision

AuraOS vise à transformer n'importe quelle machine (d'un PC portable de 2012 à une tour
gamer récente) en **console de jeu open-source** tout en conservant un poste de bureau
fonctionnel. Deux promesses contractuelles :

1. **Plancher strict de 30 FPS** sur configurations modestes (« merguez ») — jamais en
   dessous, quitte à réduire dynamiquement la résolution interne et à couper tous les effets.
2. **Zéro bridage** sur configurations musclées : 144 FPS+, VRR, refresh natif de l'écran.

## 2. Parties prenantes & cas d'usage

| Persona | Besoin principal | Critère de satisfaction |
|---|---|---|
| « Le retrogamer » | lancer des ROM + vieux `.exe` sans configurer | détection auto → ça marche au clic |
| « Le joueur Steam » | bibliothèque Steam/Proton complète | import automatique, FPS ≥ plancher |
| « Le bricoleur » | bureau + modding + émulateurs | bascule instantanée Gaming ↔ Bureau |
| « La machine de récup' » | vieux PC portable destiné aux enfants | installeur 3 étapes « effacer tout » |

## 3. Exigences fonctionnelles

### 3.1 UI — Double mode (cf. spec 02)
- **FR-UI-01** Mode Gaming par défaut au boot, sans écran de login superposé (auto-login session `aura-shell`).
- **FR-UI-02** Interface centrale unique : Bibliothèque, Récent, Paramètres, Système. Navigation manette (SDL gamecontrollerdb) + clavier/souris.
- **FR-UI-03** Transitions ≤ 16 ms (60 Hz UI) ou cadencées au taux de l'écran (144+ Hz), aucune animation bloquante.
- **FR-UI-04** Raccourci « Bureau » bascule en **&lt; 3 s** vers XFCE sans perdre l'état du launcher (processus suspendu, pas tué).
- **FR-UI-05** Retour depuis le Bureau vers le Gaming par raccourci global (combo manette) ou icône.

### 3.2 Compatibilité jeux — Agenciel (cf. spec 04)
- **FR-JV-01** Lancement de : natifs Linux, Steam (natif/Proton), Epic & GOG (Heroic Launcher headless), `.exe` autonomes, mods, émulateurs rétro.
- **FR-JV-02** Détection d'exécutable → mapping automatique : `ELF → natif` ; `.exe/.msi → Proton-GE (DXVK/VKD3D)` ; `ROM → émulateur du système` ; `.sh → sandbox` ; `AppImage → bwrap`.
- **FR-JV-03** Conteneur sandboxé par jeu : préfixe Wine dédié (bubblewrap), pas d'accès hors du dossier de jeu sauf autorisation explicite.
- **FR-JV-04** Profil par jeu : variables d'environnement, résolution interne, FPS cap, version de Proton épinglée.

### 3.3 Installation & boot (cf. spec 05)
- **FR-INS-01** ISO hybride « Live & Play » bootable UEFI **et** BIOS Legacy, testable depuis clé USB sans installation.
- **FR-INS-02** Installeur graphique 3 étapes : (1) langue/clavier, (2) mode d'installation, (3) utilisateur + résumé.
- **FR-INS-03** Mode « Effacer tout et installer AuraOS » (machine-console dédiée).
- **FR-INS-04** Mode « Dual-Boot sécurisé » : redimensionnement non destructif des partitions existantes (NTFS/ext4), sauvegarde GPT avant écriture, GRUB détectant Windows.
- **FR-INS-05** Bootloader GRUB (fallback Limine), Secure Boot optionnel (shim signé).

### 3.4 Mises à jour (cf. spec 03)
- **FR-MAJ-01** Vérification périodique (timer systemd, défaut 6 h) des releases d'un dépôt GitHub public.
- **FR-MAJ-02** Notification dans Aura Shell + « Mettre à jour » en 1 clic (téléchargement, vérification, application, redémarrage propre).
- **FR-MAJ-03** Téléchargement **delta** (zsync) quand disponible, intégrité SHA-256 + signature **minisign** obligatoire.
- **FR-MAJ-04** Application sur rootfs **A/B** : jamais de mise à jour du système en cours d'exécution ; rollback automatique en cas d'échec de boot (boot counting).
- **FR-MAJ-05** Canaux `stable` et `beta`, journal consultable, pause/reprise des téléchargements.

### 3.5 Performances (cf. aura-perf-detect)
- **FR-PERF-01** Profilage matériel au boot (`aura-perf-detect`) → 3 profils : `merguez`, `mid`, `high`.
- **FR-PERF-02** Profil **merguez** : zRAM agressif, effets UI coupés, résolution interne dynamique (plafond 720p), I/O BFQ, services de fond réduits, plancher 30 FPS.
- **FR-PERF-03** Profil **high** : governor `performance`, aucun cap FPS, refresh natif (144+ Hz), VRR, cœurs dédiés via cgroups v2, effets UI maximaux.
- **FR-PERF-04** Game-mode bas niveau : à l'activation d'un jeu, passage CPU `performance`, gel des tâches de fond non vitales (cgroup freezer), priorité I/O et scheduling du flux graphique ; restauration à la sortie.
- **FR-PERF-05** Re-profilage à chaud (`aura-perf-detect apply --profile …`) sans redémarrage.

## 4. Exigences non fonctionnelles

| ID | Exigence | Cible mesurable |
|---|---|---|
| NFR-01 | Temps de boot → UI Gaming jouable | ≤ 15 s sur SSD, ≤ 25 s sur HDD |
| NFR-02 | Empreinte disque installée | ≤ 10 Go (base + gaming layer) |
| NFR-03 | RAM à l'idle (mode Gaming) | ≤ 800 Mo (merguez) / ≤ 1,5 Go (high) |
| NFR-04 | Latence manette → action UI | ≤ 50 ms |
| NFR-05 | Disponibilité mise à jour | rollback automatique sans intervention |
| NFR-06 | Sécurité | sandbox par jeu, signatures obligatoires, pas de root dans l'UI |
| NFR-07 | Confidentialité | aucune télémétrie ; vérification MAJ = requête GitHub anonyme |
| NFR-08 | Accessibilité | navigation 100 % manette, tailles de police dynamiques, contraste AA |

## 5. Contraintes

- **C-01** Socle 100 % open-source ; aucune binaire propriétaire préinstallée (NVIDIA arrive via paquets utilisateur).
- **C-02** Tout doit fonctionner **offline** après installation (Live USB inclus) ; seules les MAJ nécessitent le réseau.
- **C-03** Le code embarqué (scripts) doit être portable Bash 5+ / POSIX-friendly, sans dépendance Python à l'exécution.
- **C-04** Compatibilité matérielle : x86_64 (AVX non requis), UEFI + BIOS, GPU Intel/AMD intégrés, NVIDIA ≥ Kepler via pilotes libres par défaut.
- **C-05** Licence des livrables : GPLv3 (scripts) ; documentation CC-BY-SA.

## 6. Livrables

1. `docs/01-architecture-globale.md` — architecture logicielle et structure des dossiers.
2. `docs/02-spec-interface-ui.md` — spécification du double mode UI.
3. `docs/03-systeme-mise-a-jour.md` + `scripts/aura-update` — pipeline de déploiement GitHub.
4. `scripts/aura-perf-detect` — profiler matériel dynamique (30 FPS ↔ 144+ FPS).
5. `scripts/aura-run`, `scripts/build-iso.sh`, unités systemd, fichiers de configuration.

## 7. Critères d'acceptation

- [ ] `bash -n` et shellcheck (niveau ≥ warning) passent sur tous les scripts livrés.
- [ ] `aura-perf-detect detect` identifie CPU/RAM/GPU/stockage et choisit un profil cohérent sur une VM 2 vCPU/2 Go (→ `merguez`) et sur une machine 8c/16 Go + GPU dédié (→ `high`).
- [ ] `aura-perf-detect apply --dry-run` n'écrit rien et liste les actions exactes.
- [ ] `aura-update check` compare sémantiquement la version locale à la dernière release GitHub et sort 0 si à jour, 10 si MAJ disponible.
- [ ] `aura-run` route correctement un `.exe` vers Proton-GE et un ELF vers l'exécution native (tests de table de mapping).
- [ ] `build-iso.sh --dry-run` affiche le plan de build complet sans agir.

## 8. Glossaire

- **Merguez** : configuration ancienne (CPU ≤ 4 cœurs, 2–4 Go RAM, IGP ou GPU sans VRAM dédiée).
- **Agenciel** : couche d'abstraction unifiée de lancement de jeux (dénomination projet).
- **Game-mode** : bascule bas niveau (governor, cgroups, I/O) à l'activation d'un jeu.
- **A/B rootfs** : deux partitions racine ; la mise à jour écrit sur l'inactive puis bascule au boot.

## 9. Jalons

| Jalon | Contenu | Dépendance |
|---|---|---|
| M1 | Socle + Live USB bootable | archiso, systemd, XFCE |
| M2 | Aura Shell mode Gaming + bascule Bureau | gamescope, Qt6 |
| M3 | Agenciel (Proton/Wine/sandbox) + aura-run | Heroic, bubblewrap |
| M4 | aura-perf-detect + game-mode | cgroups v2, zram |
| M5 | Mises à jour GitHub A/B + installeur 3 étapes | minisign, zsync, Calamares |
| M6 | Polissage perf (30 FPS merguez validé bench) | benchmark suite |
