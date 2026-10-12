#!/usr/bin/env bash
# Build the AuraOS Live prototype from the Archiso profile.
set -euo pipefail

readonly PROG="build-iso.sh"
readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROFILE_SRC="${REPO_ROOT}/iso/aura-profile"
readonly BUILD_ROOT="${REPO_ROOT}/build"
readonly WORK_DIR="${BUILD_ROOT}/work"
readonly OUT_DIR="${BUILD_ROOT}/out"

VERSION="0.1.0"
DRY_RUN=0
PUBLISH=0

log() { printf '[%s] %s\n' "${PROG}" "$*" >&2; }
die() { printf '[%s] ERREUR: %s\n' "${PROG}" "$*" >&2; exit 20; }

usage() {
  cat <<EOF
usage : sudo bash scripts/${PROG} [options]

  --version X.Y.Z   version du prototype (défaut : ${VERSION})
  --dry-run         affiche le plan sans modifier de fichiers
  --publish         publication désactivée pour cette image prototype
  -h, --help        cette aide
EOF
}

while (( $# )); do
  case "$1" in
    --version)
      (( $# >= 2 )) || die "--version attend une valeur"
      VERSION="$2"; shift ;;
    --version=*) VERSION="${1#*=}" ;;
    --dry-run) DRY_RUN=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "option inconnue : $1" ;;
  esac
  shift
done

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]] || die "version invalide : ${VERSION}"
(( PUBLISH == 0 )) || die "la publication est désactivée pour cette image prototype"

readonly ISO_NAME="auraos-${VERSION}-x86_64.iso"
readonly STAGE_DIR="${BUILD_ROOT}/profile-${VERSION}"

plan() {
  cat >&2 <<EOF
BUILD DU PROTOTYPE LIVE AURAOS
  Profil : ${PROFILE_SRC}
  Staging isolé : ${STAGE_DIR}
  Sortie : ${OUT_DIR}/${ISO_NAME}
  Mode : Live XFCE basé sur Archiso ; aucun installateur ni mode gaming intégré
  Publication et signature : non configurées pour le prototype
EOF
}
plan

(( DRY_RUN )) && { log "dry-run : aucune modification effectuée"; exit 0; }
[[ ${EUID} -eq 0 ]] || die "droits root requis par mkarchiso"
[[ -d "${PROFILE_SRC}" ]] || die "profil Archiso introuvable : ${PROFILE_SRC}"
[[ -f "${PROFILE_SRC}/profiledef.sh" && -f "${PROFILE_SRC}/packages.x86_64" && -f "${PROFILE_SRC}/pacman.conf" ]] || die "profil incomplet"
command -v mkarchiso >/dev/null 2>&1 || die "outil manquant : mkarchiso (paquet Arch : archiso)"

# Ensure destructive cleanup remains confined to the repository build directory.
[[ "${BUILD_ROOT}" == "${REPO_ROOT}/build" && "${BUILD_ROOT}" != "/" ]] || die "chemin de build inattendu"
mkdir -p "${BUILD_ROOT}" "${OUT_DIR}"
rm -rf -- "${STAGE_DIR}" "${WORK_DIR}"
mkdir -p "${STAGE_DIR}" "${WORK_DIR}"
cp -a "${PROFILE_SRC}/." "${STAGE_DIR}/"

# Copy runtime utilities only into the disposable staging profile.
install -d "${STAGE_DIR}/airootfs/usr/lib/aura/bin" "${STAGE_DIR}/airootfs/etc/aura"
install -m 0755 "${REPO_ROOT}/scripts/aura-perf-detect" "${STAGE_DIR}/airootfs/usr/lib/aura/bin/"
install -m 0755 "${REPO_ROOT}/scripts/aura-update" "${STAGE_DIR}/airootfs/usr/lib/aura/bin/"
install -m 0755 "${REPO_ROOT}/scripts/aura-run" "${STAGE_DIR}/airootfs/usr/lib/aura/bin/"
install -m 0644 "${REPO_ROOT}/etc/aura/aura.conf" "${REPO_ROOT}/etc/aura/update.conf" "${STAGE_DIR}/airootfs/etc/aura/"
install -d "${STAGE_DIR}/airootfs/usr/local/bin"
install -m 0755 "${PROFILE_SRC}/airootfs/usr/local/bin/aura-live-info" \
  "${STAGE_DIR}/airootfs/usr/local/bin/aura-live-info"

log "construction mkarchiso (cela peut prendre plusieurs minutes)"
mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${STAGE_DIR}"

BUILT_ISO="$(printf '%s\n' "${OUT_DIR}"/*.iso | sort | tail -n 1)"
[[ -s "${BUILT_ISO}" ]] || die "aucune ISO produite dans ${OUT_DIR}"
if [[ "${BUILT_ISO}" != "${OUT_DIR}/${ISO_NAME}" ]]; then
  mv -- "${BUILT_ISO}" "${OUT_DIR}/${ISO_NAME}"
fi
sha256sum "${OUT_DIR}/${ISO_NAME}" > "${OUT_DIR}/${ISO_NAME}.sha256"
log "ISO produite (boot non encore validé) : ${OUT_DIR}/${ISO_NAME}"
log "Empreinte : ${OUT_DIR}/${ISO_NAME}.sha256"
