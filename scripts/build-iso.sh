#!/usr/bin/env bash
# Build the AuraOS Live prototype from the Archiso profile.
set -euo pipefail

readonly PROG="build-iso.sh"
readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROFILE_SRC="${REPO_ROOT}/iso/aura-profile"
readonly BUILD_ROOT="${REPO_ROOT}/build"
readonly WORK_DIR="${BUILD_ROOT}/work"
readonly OUT_DIR="${BUILD_ROOT}/out"
# Profil de référence fourni par le paquet archiso ; sert de base (paquets de
# base + configuration des chargeurs de démarrage). Surchargeable par variable.
readonly ARCHISO_RELENG="${ARCHISO_RELENG:-/usr/share/archiso/configs/releng}"

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

# Fusionne des listes de paquets : conserve les commentaires et déduplique les
# paquets (la base releng d'abord, puis les ajouts AuraOS).
# Une ligne « #!remove <paquet> » dans le fichier d'ajouts retire ce paquet de la
# base releng : indispensable pour remplacer une variante par une autre (ex.
# virtualbox-guest-utils-nox -> virtualbox-guest-utils, sinon conflit pacman).
merge_packages() {
  local base="$1" additions="$2"
  awk -v base="${base}" '
    FILENAME == base { lines[++n] = $0; next }
    /^[[:space:]]*#![[:space:]]*remove[[:space:]]+/ {
      p = $0
      sub(/^[[:space:]]*#![[:space:]]*remove[[:space:]]+/, "", p)
      sub(/[[:space:]]+$/, "", p)
      if (p != "") removed[p] = 1
      next
    }
    { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        s = lines[i]
        t = s
        sub(/^[[:space:]]+/, "", t)
        sub(/[[:space:]]+$/, "", t)
        if (t == "" || t ~ /^#/) { print s; continue }
        if (t in removed) continue
        if (seen[t]++) continue
        print t
      }
    }
  ' "${base}" "${additions}"
}

# Donne une identité AuraOS aux écrans de démarrage hérités du profil releng.
# Les entrées portent sinon les étiquettes « Arch Linux install medium » : on
# réécrit uniquement le texte visible, sans toucher aux noms de fichiers, aux
# binaires EFI ni aux lignes de commande du noyau.
brand_boot_configs() {
  local dir f
  for dir in "${STAGE_DIR}/syslinux" "${STAGE_DIR}/efiboot"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r -d '' f; do
      sed -i -E \
        -e 's/Arch Linux install medium/AuraOS Live/g' \
        -e 's/Arch Linux/AuraOS/g' \
        "$f"
    done < <(find "${dir}" -type f \( -name '*.cfg' -o -name '*.conf' \) -print0)
  done

  # systemd-boot : laisser un court délai pour choisir une entrée au démarrage.
  local loader="${STAGE_DIR}/efiboot/loader/loader.conf"
  if [[ -f "${loader}" ]]; then
    if grep -qE '^[[:space:]]*timeout' "${loader}"; then
      sed -i -E 's/^[[:space:]]*timeout.*/timeout 15/' "${loader}"
    else
      printf 'timeout 15\n' >> "${loader}"
    fi
  fi
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
  Base : ${ARCHISO_RELENG} (paquets de base + configs de démarrage)
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
[[ -d "${ARCHISO_RELENG}" ]] || die "profil releng d'archiso introuvable : ${ARCHISO_RELENG} (installez le paquet archiso)"

# Ensure destructive cleanup remains confined to the repository build directory.
[[ "${BUILD_ROOT}" == "${REPO_ROOT}/build" && "${BUILD_ROOT}" != "/" ]] || die "chemin de build inattendu"
mkdir -p "${BUILD_ROOT}" "${OUT_DIR}"
rm -rf -- "${STAGE_DIR}" "${WORK_DIR}"
mkdir -p "${STAGE_DIR}" "${WORK_DIR}"
cp -a "${PROFILE_SRC}/." "${STAGE_DIR}/"

# Compléter le profil avec la base fournie par le paquet archiso : les fichiers
# de démarrage (syslinux/efiboot) et la liste des paquets de base (noyau,
# mkinitcpio-archiso, base, etc.). Cela évite les erreurs « boot mode » et
# « no kernel » et garde le profil cohérent avec la version installée d'archiso.
for bootdir in syslinux efiboot grub; do
  if [[ -d "${ARCHISO_RELENG}/${bootdir}" && ! -e "${STAGE_DIR}/${bootdir}" ]]; then
    cp -a "${ARCHISO_RELENG}/${bootdir}" "${STAGE_DIR}/${bootdir}"
    log "config de démarrage copiée depuis releng : ${bootdir}/"
  fi
done
[[ -d "${STAGE_DIR}/syslinux" ]] || die "syslinux/ absent (requis par bios.syslinux)"
[[ -d "${STAGE_DIR}/efiboot" ]]  || die "efiboot/ absent (requis par uefi.systemd-boot)"

brand_boot_configs
log "identité de démarrage AuraOS appliquée (titres du menu de boot)"

merge_packages "${ARCHISO_RELENG}/packages.x86_64" "${PROFILE_SRC}/packages.x86_64" \
  > "${STAGE_DIR}/packages.x86_64"
log "liste des paquets fusionnée (base releng + ajouts AuraOS)"
# Contrôle : la variante VirtualBox retenue ne doit pas laisser les deux variantes
# incompatibles dans la liste fusionnée (cause du conflit pacman observé).
if grep -qx 'virtualbox-guest-utils' "${STAGE_DIR}/packages.x86_64" \
   && grep -qx 'virtualbox-guest-utils-nox' "${STAGE_DIR}/packages.x86_64"; then
  die "liste fusionnée incohérente : virtualbox-guest-utils et -nox cohabitent"
fi

# Copy runtime utilities only into the disposable staging profile.
install -d "${STAGE_DIR}/airootfs/usr/lib/aura/bin" "${STAGE_DIR}/airootfs/etc/aura" "${STAGE_DIR}/airootfs/etc"
install -m 0755 "${REPO_ROOT}/scripts/aura-perf-detect" "${STAGE_DIR}/airootfs/usr/lib/aura/bin/"
install -m 0755 "${REPO_ROOT}/scripts/aura-update" "${STAGE_DIR}/airootfs/usr/lib/aura/bin/"
install -m 0755 "${REPO_ROOT}/scripts/aura-run" "${STAGE_DIR}/airootfs/usr/lib/aura/bin/"
install -m 0644 "${REPO_ROOT}/etc/aura/aura.conf" "${REPO_ROOT}/etc/aura/update.conf" "${STAGE_DIR}/airootfs/etc/aura/"
install -m 0644 "${PROFILE_SRC}/pacman.conf" "${STAGE_DIR}/airootfs/etc/pacman.conf"
install -d "${STAGE_DIR}/airootfs/usr/local/bin"
install -m 0755 "${PROFILE_SRC}/airootfs/usr/local/bin/aura-live-info" \
  "${STAGE_DIR}/airootfs/usr/local/bin/aura-live-info"
install -m 0755 "${REPO_ROOT}/scripts/aura-set-wallpaper" \
  "${STAGE_DIR}/airootfs/usr/local/bin/aura-set-wallpaper"

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
