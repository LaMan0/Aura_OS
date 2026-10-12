#!/usr/bin/env bash
# =============================================================================
# build-iso.sh — Construction de l'ISO hybride « Live & Play » d'AuraOS
# -----------------------------------------------------------------------------
# Produit une image ISO bootable UEFI + BIOS Legacy à partir du profil archiso,
# puis (optionnellement) signe et publie la release sur GitHub.
#
# Usage :
#   sudo ./build-iso.sh --version 1.0.0 [--channel stable] [--dry-run] [--publish]
#
# Sorties (dossier ./out) :
#   AuraOS-<version>-x86_64.iso          image hybride Live + installeur
#   AuraOS-<version>-x86_64.iso.sha256   empreinte SHA-256
#   AuraOS-<version>-x86_64.iso.zsync    delta pour les mises à jour
#   SHA256SUMS(.minisig)                  manifeste signé (minisign)
# =============================================================================
set -euo pipefail

readonly PROG="build-iso.sh"
readonly HERE="$(cd "$(dirname "$0")" && pwd)"
readonly PROFILE_SRC="${HERE}/../iso/aura-profile"
readonly WORK_DIR="${HERE}/../build/work"
readonly OUT_DIR="${HERE}/../build/out"

VERSION="1.0.0"
CHANNEL="stable"
DRY_RUN=0
PUBLISH=0

log() { printf '[%s] %s\n' "${PROG}" "$*" >&2; }
die() { printf '[%s] ERREUR: %s\n' "${PROG}" "$*" >&2; exit 20; }

usage() {
  cat <<EOF
usage : sudo ${PROG} --version X.Y.Z [options]

  --version X.Y.Z   version de la release (défaut : ${VERSION})
  --channel C       stable | beta (défaut : ${CHANNEL})
  --dry-run         affiche le plan de build sans rien construire
  --publish         publie la release sur GitHub (nécessite gh authentifié)
  -h, --help        cette aide
EOF
}

while (( $# )); do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --version=*) VERSION="${1#*=}" ;;
    --channel) CHANNEL="$2"; shift ;;
    --channel=*) CHANNEL="${1#*=}" ;;
    --dry-run) DRY_RUN=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "option inconnue : $1" ;;
  esac
  shift
done

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]] || die "version invalide : ${VERSION}"
[[ "${CHANNEL}" =~ ^(stable|beta)$ ]] || die "canal invalide : ${CHANNEL}"

ISO_NAME="AuraOS-${VERSION}-x86_64.iso"

log "════════════════════════════════════════════════════════"
log "  Build AuraOS ${VERSION} (canal ${CHANNEL})"
log "════════════════════════════════════════════════════════"

# --- Étape 0 : plan de build (toujours affiché) ----------------------------
plan() {
  cat >&2 <<EOF
PLAN DE BUILD
  1. Vérification de l'outillage   : archiso, mksquashfs, xorriso, minisign, zsyncmake
  2. Profil ISO                    : ${PROFILE_SRC}
  3. Nettoyage                     : ${WORK_DIR}
  4. mkarchiso                     : image hybride UEFI (systemd-boot/shim) + BIOS (isolinux)
  5. Intégration                   : aura-perf-detect · aura-update · aura-run · unités systemd
                                     Aura Shell · XFCE · Proton-GE · Calamares (installeur 3 étapes)
  6. Sortie                        : ${OUT_DIR}/${ISO_NAME}
  7. Signature                     : SHA256SUMS + minisign (clé : /etc/aura/update.pub)
  8. Delta                         : zsyncmake → ${ISO_NAME}.zsync
  9. Publication GitHub (si --publish) : release v${VERSION} + assets
EOF
}
plan

(( DRY_RUN )) && { log "dry-run : arrêt avant toute modification"; exit 0; }
[[ ${EUID} -eq 0 ]] || die "droits root requis (mkarchiso)"

# --- Étape 1 : outillage ----------------------------------------------------
for tool in mkarchiso mksquashfs xorriso zsyncmake; do
  command -v "${tool}" >/dev/null 2>&1 || die "outil manquant : ${tool} (paquet : archiso / squashfs-tools / zsync)"
done
log "outillage vérifié"

# --- Étape 2 : préparation du profil archiso --------------------------------
[[ -d "${PROFILE_SRC}" ]] || die "profil archiso introuvable : ${PROFILE_SRC}"
log "profil archiso : ${PROFILE_SRC}"

# Injection des scripts du dépôt dans l'arbre de l'image
mkdir -p "${PROFILE_SRC}/airootfs/usr/lib/aura/bin"
cp -f "${HERE}/aura-perf-detect" "${PROFILE_SRC}/airootfs/usr/lib/aura/bin/"
cp -f "${HERE}/aura-update"      "${PROFILE_SRC}/airootfs/usr/lib/aura/bin/"
cp -f "${HERE}/aura-run"         "${PROFILE_SRC}/airootfs/usr/lib/aura/bin/"
chmod 755 "${PROFILE_SRC}/airootfs/usr/lib/aura/bin/"*

mkdir -p "${PROFILE_SRC}/airootfs/etc/systemd/system"
cp -f "${HERE}/../systemd/"*.service "${HERE}/../systemd/"*.timer \
      "${PROFILE_SRC}/airootfs/etc/systemd/system/" 2>/dev/null || true

mkdir -p "${PROFILE_SRC}/airootfs/etc/aura"
cp -f "${HERE}/../etc/aura/"*.conf "${PROFILE_SRC}/airootfs/etc/aura/"
log "scripts et unités injectés dans l'image"

# --- Étape 3 : nettoyage puis build ----------------------------------------
log "nettoyage de ${WORK_DIR}…"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${OUT_DIR}"

log "mkarchiso en cours (plusieurs minutes)…"
mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_SRC}"
[[ -s "${OUT_DIR}/${ISO_NAME}" ]] || die "ISO non produite"
log "ISO produite : ${OUT_DIR}/${ISO_NAME}"

# --- Étape 4 : empreintes & signature --------------------------------------
(
  cd "${OUT_DIR}"
  sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"
  sha256sum "${ISO_NAME}" > SHA256SUMS
  if command -v minisign >/dev/null 2>&1 && [[ -r /etc/aura/update.key ]]; then
    minisign -Sm SHA256SUMS -s /etc/aura/update.key
    log "SHA256SUMS signé (minisign)"
  else
    log "AVERTISSEMENT : minisign ou clé absente — release NON signée"
  fi
  zsyncmake -u "https://github.com/AuraOS-Project/auraos/releases/download/v${VERSION}/${ISO_NAME}" "${ISO_NAME}"
  log "delta zsync produit"
)

# --- Étape 5 : publication GitHub (optionnel) ------------------------------
if (( PUBLISH )); then
  command -v gh >/dev/null 2>&1 || die "CLI gh requise pour --publish"
  log "publication de la release v${VERSION}…"
  gh release create "v${VERSION}" \
      --repo AuraOS-Project/auraos \
      --title "AuraOS v${VERSION}" \
      --notes "Release ${CHANNEL} d'AuraOS ${VERSION}" \
      $([[ "${CHANNEL}" == "beta" ]] && echo "--prerelease") \
      "${OUT_DIR}/${ISO_NAME}" \
      "${OUT_DIR}/${ISO_NAME}.sha256" \
      "${OUT_DIR}/${ISO_NAME}.zsync" \
      "${OUT_DIR}/SHA256SUMS" \
      $([[ -f "${OUT_DIR}/SHA256SUMS.minisig" ]] && echo "${OUT_DIR}/SHA256SUMS.minisig")
  log "release publiée"
fi

log "════════════════════════════════════════════════════════"
log "  BUILD TERMINÉ : ${OUT_DIR}/${ISO_NAME}"
log "  Flash : sudo dd if=${OUT_DIR}/${ISO_NAME} of=/dev/sdX bs=4M status=progress conv=fsync"
log "════════════════════════════════════════════════════════"
