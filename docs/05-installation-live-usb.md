# 05 — Installation : clé USB « Live & Play », installeur 3 étapes, dual-boot

## 1. Clé USB « Live & Play »

L'ISO produite par [`scripts/build-iso.sh`](../scripts/build-iso.sh) est **hybride** :
bootable UEFI (systemd-boot/shim) **et** BIOS Legacy (isolinux), sur n'importe quelle
clé USB ou DVD.

```bash
# Flash (Linux/macOS) — DÉTRUIT la clé cible
sudo dd if=AuraOS-1.0.0-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync

# Flash (Windows) : Rufus ou balenaEtcher, mode DD brut (pas ISO→USB)
```

Comportement Live :
- **Live & Play** : AuraOS tourne entièrement depuis la clé (RAM + zRAM, système en squashfs
  compressé) ; les jeux peuvent être lancés depuis une 2ᵉ clé ou un disque externe.
- **Persistance optionnelle** : partition `casper-rw`-style (overlay) pour conserver
  réglages et petits fichiers entre deux sessions.
- L'accès au disque dur local est possible mais **jamais modifié** hors installeur.

## 2. Installeur graphique intelligent (Calamares) — 3 étapes

```
Étape 1 — LANGUE & CLAVIER        (détection auto + choix manuel)
Étape 2 — MODE D'INSTALLATION     ├─ [Effacer tout et installer AuraOS]
                                  └─ [Dual-Boot sécurisé avec <OS existant>]
Étape 3 — UTILISATEUR & RÉSUMÉ    (nom, mot de passe, auto-login Gaming, récapitulatif
                                    des partitions avant validation IRRÉVERSIBLE)
```

### Mode « Effacer tout » (machine-console dédiée)
- Partitionnement automatique du schéma de l'architecture 01 (ESP 512 Mo, boot 1 Go,
  rootA/rootB 20 Go, /var, /home, swapfile).
- Confirmation double obligatoire (« EFFACER » en toutes lettres) car destructive.
- Installe les deux slots racine identiques → système immédiatement prêt pour les MAJ A/B.

### Mode « Dual-Boot sécurisé » (sans perte de données)
1. **Sauvegarde de la table de partition** : `sgdisk --backup` sur la clé USB (restaurable).
2. **Redimensionnement non destructif** : `ntfsresize` (Windows NTFS) ou `resize2fs` (ext4),
   avec vérification préalable (`chkdsk` exigé sur NTFS, démontage propre exigé).
3. Espace récupéré ≥ 40 Go recommandé ; sinon l'installeur refuse proprement.
4. Installation d'AuraOS dans l'espace libéré + création des slots A/B.
5. **GRUB** régénéré avec `os-prober` : entrées « AuraOS » et « Windows Boot Manager ».
6. Redémarrage : le menu GRUB propose les deux systèmes, défaut AuraOS (timeout 5 s).

**Garanties** :
- Aucune écriture sur la partition Windows existante (lecture seule pendant tout le processus).
- La table GPT originale est sauvegardée et restaurable en une commande.
- En cas d'échec d'installation, l'ancien bootloader Windows est restauré automatiquement.

## 3. Bootloader & Secure Boot

- **GRUB** par défaut (A/B via `grubenv` : `aura_slot=A|B`, compteur `boot_count`).
- **Limine** en alternative expérimentale (boot plus rapide, configuration minimale).
- **Secure Boot** : shim signé + GRUB signé ; les modules noyau tiers (NVIDIA) exigent
  alors l'enrôlement MOK (`mokutil`) — désactivable dans le BIOS.

## 4. Premier boot post-installation

1. `aura-perf-detect.service` profile le matériel (merguez/mid/high).
2. Auto-login sur la session `aura-shell` → mode Gaming.
3. Assistant de première utilisation dans l'UI : réseau, compte Steam (optionnel),
   bibliothèque de jeux (détection automatique), vérification des mises à jour.

## 5. Dépannage rapide

| Symptôme | Cause probable | Action |
|---|---|---|
| L'ISO ne boot pas | clé flashée en mode ISO au lieu de DD | refaire avec Rufus (mode DD) |
| Écran noir (NVIDIA) | modesetting | `nomodeset` temporaire dans GRUB, puis installer le pilote |
| Boot en boucle après MAJ | échec du nouveau slot | boot counting bascule auto sur l'ancien ; sinon `aura-update rollback` |
| Windows absent du GRUB | os-prober désactivé | `sudo os-prober && sudo grub-mkconfig -o /boot/grub/grub.cfg` |
| 30 FPS non tenus sur merguez | profil non appliqué | `sudo aura-perf-detect apply --profile merguez` |
