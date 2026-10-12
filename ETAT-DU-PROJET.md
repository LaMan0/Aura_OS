# ETAT-DU-PROJET.md — AuraOS : synthèse complète
**Date :** 12 octobre 2026 · **Projet :** `nomos_OS` (C:\Users\maeno\Documents\nomos_OS)
**Objet :** synthèse de l'avancement, des limites et des prochaines étapes.

---

## 1. État actuel

AuraOS reste un projet de conception et de prototypage. Un premier profil Archiso Live a été ajouté pour tenter de générer une image de démonstration Arch Linux + XFCE. **Aucun build réel ni démarrage de cette image n'a encore été confirmé.** Ce prototype ne doit pas être présenté comme l'OS gaming complet.

### Présent dans le dépôt

- Cahier des charges et architecture (docs 00 à 06).
- Scripts Bash AuraOS : `aura-perf-detect`, `aura-update`, `aura-run`, `aura-vault`, `bench-fps.sh`.
- Services et configurations de référence sous `systemd/` et `etc/aura/`.
- Maquette web UI sous `preview/index.html` (ce n'est pas une interface de système démarrable).
- Profil Archiso initial sous `iso/aura-profile/` : XFCE, LightDM, NetworkManager et réglages destinés au Live.
- `scripts/build-iso.sh` pour tenter de construire cette image sans modifier le profil source.

### Pas encore livré/validé

- ISO construite et démarrée dans QEMU ou VirtualBox.
- Aura Shell Qt/QML et session gaming.
- Installeur Calamares configuré et validé, partitionnement, dual-boot.
- Secure Boot, persistance, mises à jour A/B, signature de release.
- Fonctionnement réel des scripts root sous Linux avec systemd, cgroups, zRAM, pilotes.
- Tests de compatibilité GPU/jeux et mesures réelles du plancher 30 FPS.

## 2. Prochaine étape — PoC Live

Sur une VM Arch Linux dédiée, installer `archiso`, exécuter :

```bash
bash -n scripts/build-iso.sh iso/aura-profile/profiledef.sh \
  iso/aura-profile/airootfs/root/customize_airootfs.sh
bash scripts/build-iso.sh --dry-run
sudo bash scripts/build-iso.sh --version 0.1.0
```

Puis vérifier le SHA-256 et démarrer l'ISO dans une VM VirtualBox séparée, en mode Live seulement. Le parcours détaillé est dans `Instruction_Boot_AuraOS` ; les éléments du profil et leurs limites sont dans `iso/README-iso.md`.

## 3. Points à vérifier/corriger après le build

1. La configuration Archiso et les noms des boot modes par rapport à la version d'Archiso installée.
2. Construction réelle de l'image, production du bon nom de fichier et empreinte valide.
3. Connexion LightDM automatique sur XFCE ; démarrage et arrêt de la VM.
4. Réseau invité et compatibilité des paquets VirtualBox.
5. Boot UEFI et BIOS uniquement si chacun est testé séparément.

Ne pas installer sur disque, partitionner, brancher de disque physique à la VM ou flasher une clé de production avec une image non validée.

---
*État rédigé le 12 octobre 2026 ; mise à jour requise après le premier build et le premier test VirtualBox.*
