# 03 — Système de mise à jour (pipeline GitHub Releases)

## 1. Vue d'ensemble

```
                    dépôt GitHub public : AuraOS-Project/auraos
   ┌──────────────────────────────────────────────────────────────────┐
   │  Release v1.2.0                                                  │
   │   ├── AuraOS-1.2.0-x86_64.iso.zsync      (delta image complète) │
   │   ├── aura-system-1.2.0.sqfs.zsync       (delta rootfs — rapide) │
   │   ├── aura-system-1.2.0.sqfs             (image complète fallback)│
   │   ├── SHA256SUMS                         (empreintes)            │
   │   └── SHA256SUMS.minisig                 (signature minisign)    │
   └──────────────────────────────────────────────────────────────────┘
                ▲ 1. poll (GET /releases/latest, ETag)
                │ 2. download delta (zsync, reprise possible)
   ┌────────────┴─────────────┐     ┌───────────────────────────────┐
   │ aura-update.service      │────▶│ VÉRIFICATION                  │
   │ (timer 6 h, défaut)      │     │  sha256 -c SHA256SUMS         │
   └──────────────────────────┘     │  minisign -Vm SHA256SUMS      │
                                    │  (clé publique épinglée)      │
                                    └──────────────┬────────────────┘
                                                   ▼
                          ┌─────────────────────────────────────────┐
                          │ APPLICATION (rootfs A/B)                │
                          │  écriture du slot INACTIF (rootA/rootB) │
                          │  mise à jour des entrées GRUB + compteur│
                          │  bascule au redémarrage                  │
                          └─────────────────────────────────────────┘
                                                   ▼
                          ┌─────────────────────────────────────────┐
                          │ BOOT : boot counting (3 essais)         │
                          │  échec → retour automatique au slot sain│
                          └─────────────────────────────────────────┘
```

## 2. Composants

| Composant | Rôle |
|---|---|
| `aura-update.timer` | déclenche `aura-update check` toutes les 6 h (aléatoire ± 30 min) |
| `aura-update.service` | exécution oneshot : check / download / apply selon l'état |
| `scripts/aura-update` | CLI complet (état machine, verrous, téléchargement, vérification, bascule) |
| `/etc/aura/update.conf` | dépôt GitHub, canal (`stable`/`beta`), clé minisign, proxy |
| `/var/lib/aura/state.json` | version installée, version disponible, progression, historique |
| Aura Shell (onglet Système) | notification + bouton « Mettre à jour » (1-clic) |

## 3. Format des releases GitHub

- **Tag** sémantique : `vMAJOR.MINOR.PATCH[-beta.N]`.
- Chaque release contient `SHA256SUMS` et `SHA256SUMS.minisig` (signature **minisign** ; clé publique
  livrée dans `/etc/aura/update.conf` — jamais téléchargée depuis GitHub).
- Le **delta** est produit par `zsyncmake` sur l'image `.sqfs` (blocs 2 Mo) : un client ne
  télécharge que les blocs modifiés par rapport à l'image locale (typiquement 5–15 % de l'image).
- Assets nommés de façon stricte (`aura-system-<version>-<arch>.sqfs[.zsync]`) → parsables sans ambiguïté.

## 4. Machine à états du client

```
  IDLE ──check()──▶ UPDATE_AVAILABLE ──download()──▶ DOWNLOADING ──▶ DOWNLOADED
   ▲                    │  (resume -C -)                  │ échec → IDLE (retry)
   │                    └──────── pause ──────────────────┘
   │                                                        │ verify()
   │                                                        ▼
   │                                                   VERIFIED ──apply()──▶ APPLYING
   │                                                                        │ échec →
   ├─────────────────────────────────────────────────────────────────────────┘ rollback
   └──── reboot ── boot OK (compteur remis à zéro)  ou  BOOT_FAILED → slot précédent
```

Règles strictes :
1. **Aucune écriture sur le slot actif** — la mise à jour est écrite sur le slot inactif.
2. **Aucune application sans vérification cryptographique** (SHA-256 *et* signature).
3. **Un seul processus de MAJ** à la fois (`flock` sur `/var/lib/aura/update.lock`).
4. Reprise de téléchargement : `zsync`/`curl -C -`, vérification par blocs, TTL de cache 7 j.
5. Redémarrage **jamais brutal** : avertissement 10 s dans l'UI, arrêt propre des sessions.

## 5. API GitHub consommée

```bash
# Dernière release (avec ETag pour éviter de re-télécharger les métadonnées)
curl -fsSL -H "Accept: application/vnd.github+json" \
     -H "If-None-Match: <etag-caché>" \
     https://api.github.com/repos/AuraOS-Project/auraos/releases/latest
# → 304 : rien de nouveau · 200 : JSON (tag_name, assets[], published_at…)
```

- Rate limit : 60 req/h non authentifiées → polling à 6 h largement suffisant ; cache ETag local.
- Canal `beta` : `/releases` complet, filtre sur `prerelease=false` (stable) ou inclus (beta).
- Aucune donnée utilisateur n'est transmise ; l'User-Agent est `aura-update/<version>`.

## 6. Rollback & récupération

- **Boot counting** GRUB (`boot_once`, `boot_success`) : 3 tentatives infructueuses → retour automatique au slot précédent.
- `aura-update rollback` manuel : bascule forcée + reconstruction de l'entrée GRUB.
- `/var` et `/home` ne sont jamais touchés par les MAJ (données préservées y compris en rollback).
- Échec réseau : retry exponentiel (5 min → 1 h), journal `/var/log/aura-update.log`.

## 7. Expérience « 1-clic »

1. `aura-update.timer` détecte `v1.2.0 > v1.1.0` → écrit `state.json` + notification D-Bus.
2. Aura Shell affiche la carte MAJ (taille delta, notes de version cliquables).
3. L'utilisateur clique **[ Mettre à jour ]** → `aura-update apply --reboot` :
   téléchargement (barre de progression dans l'UI via `state.json`), vérification, application,
   compte à rebours 10 s (annulable), redémarrage propre.
4. Au boot suivant : « AuraOS v1.2.0 est installé » ; en cas d'échec : reboot sur l'ancien slot + notification explicative.

## 8. Sécurité de la chaîne

- Clé minisign **publique** épinglée dans l'image ; rotation des clés = release signée par l'ancienne **et** la nouvelle clé.
- HTTPS obligatoire (HSTS côté GitHub), empreintes vérifiées avant écriture, espace disque pré-vérifié (≥ 2× taille image).
- Le script refuse toute URL non `https://github.com/AuraOS-Project/` (ou domaine miroir déclaré dans `update.conf`).
