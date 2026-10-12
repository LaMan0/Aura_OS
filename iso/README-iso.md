# Profil ISO AuraOS — prototype Live 0.1

## Périmètre

`aura-profile/` est un profil Archiso de démonstration basé sur Arch Linux Live. Il vise un démarrage Live UEFI/BIOS dans VirtualBox avec XFCE et un compte de session `aura` à connexion automatique. Il ne constitue pas l'OS gaming prévu : Aura Shell, Steam/Proton, l'installeur, le dual-boot, les mises à jour A/B, la persistance et Secure Boot ne sont pas inclus ou validés.

Le profil s'inspire du profil officiel Archiso `releng`. Vérifier la syntaxe et les chemins contre la version d'Archiso installée avant toute construction : les interfaces du profil peuvent évoluer.

## Structure actuelle

```text
iso/aura-profile/
├── profiledef.sh
├── packages.x86_64
├── pacman.conf
└── airootfs/
    ├── etc/lightdm/lightdm.conf
    ├── etc/systemd/system/...
    ├── etc/skel/Desktop/AuraOS-prototype.txt
    ├── etc/skel/.xinitrc
    ├── root/customize_airootfs.sh
    └── usr/local/bin/aura-live-info
```

Paquets ajoutés au profil `releng` : XFCE, LightDM, greeter GTK, NetworkManager, Xorg et les utilitaires invités VirtualBox. La base Archiso apporte notamment noyau, firmware et mécanismes Live.

## Construction

À faire dans une installation Arch Linux dédiée (par exemple une VM de build séparée sur Windows). Installez `archiso`, puis depuis la racine du dépôt :

```bash
bash -n scripts/build-iso.sh
bash scripts/build-iso.sh --dry-run
sudo bash scripts/build-iso.sh --version 0.1.0
```

Le build nettoie uniquement `build/work` et `build/profile-<version>` du dépôt, et écrit dans `build/out/`. Il ne modifie pas le profil source. Il exige `mkarchiso`; les dépendances sont fournies par le paquet Arch `archiso`. Il écrit une empreinte SHA-256 mais ne signe ni ne publie le prototype.

**Le résultat n'est pas certifié bootable avant un test.** Vérifiez le hash et démarrez l'ISO obtenue dans VirtualBox, d'abord en Live uniquement. N'attachez aucun disque physique et ne lancez pas d'outil de partitionnement.

## Test manuel attendu

1. Vérifier que l'ISO et son `.sha256` existent dans `build/out/` et que `sha256sum -c` répond `OK`.
2. Créer une VM VirtualBox x86_64, 2–4 vCPU et 4–8 Go RAM selon les ressources disponibles.
3. Activer EFI pour le test UEFI, attacher l'ISO comme lecteur optique et démarrer.
4. Confirmer l'ouverture de session XFCE, le réseau si disponible, et `aura-live-info` dans un terminal.
5. Noter version VirtualBox, réglages, erreurs et résultat. Répéter sans EFI uniquement si le mode BIOS est revendiqué/testé.

Ne pas inclure d'installeur/partitionneur dans le prototype. Les unités de performance et de mise à jour ne sont pas activées automatiquement.
