#!/usr/bin/env bash
# =============================================================================
# bench-fps.sh — Suite de benchmarks AuraOS : mesure 1% low FPS & validation
#                du plancher contractuel (30 FPS sur profil "merguez")
# -----------------------------------------------------------------------------
# Mesure une session de jeu (trace de frametimes), calcule les métriques
# standard du jeu PC et tranche : le plancher est-il tenu ?
#
#   · avg FPS          : images / durée réelle
#   · 1% low           : moyenne des FPS des 1 % d'images les plus lentes
#   · 0.1% low         : moyenne des FPS des 0,1 % les plus lentes (micro-freezes)
#   · P1 FPS           : 1er percentile des FPS par image (99 % vont plus vite)
#   · P99 frametime    : 99e percentile des temps d'image (ms)
#   · stutters         : images > 2× la médiane ET > 50 ms
#
# Commandes :
#   run -- <commande de jeu...>   lance et mesure (backend mangohud)
#   analyse --input TRACE         analyse une trace frametimes hors-ligne
#   report                        agrège les résultats + badges "Verified 30 FPS"
#   self-test                     vérifie le moteur statistique (fixture connue)
#
# Formats de trace acceptés (auto-détection) :
#   · CSV avec en-tête contenant une colonne "frametime" (ms) ou "fps"
#   · une valeur de frametime (ms) par ligne
#   · lignes commençant par # ignorées
#
# Codes de sortie : 0 = plancher TENU · 10 = plancher NON tenu · 20 = erreur
# =============================================================================
set -euo pipefail

readonly PROG="bench-fps.sh"
readonly CONF_DIR="${AURA_CONF_DIR:-/etc/aura}"
readonly PROFILE_CONF="${CONF_DIR}/perf-profile.conf"
readonly BENCH_DIR="${AURA_BENCH_DIR:-/var/lib/aura/bench}"
readonly RESULTS="${BENCH_DIR}/results.jsonl"
readonly VERIFIED="${BENCH_DIR}/verified.jsonl"

log()  { printf '[%s] %s\n' "${PROG}" "$*" >&2; }
die()  { printf '[%s] ERREUR: %s\n' "${PROG}" "$*" >&2; exit 20; }

GAME="" PROFILE="" FLOOR="" DURATION=120 BACKEND="auto" INPUT="" OUTPUT="" MARK=0
GAME_CMD=()

# -----------------------------------------------------------------------------
# Profil & plancher
# -----------------------------------------------------------------------------
resolve_profile() {
  # Priorité : --profile > perf-profile.conf > mid
  if [[ -z "${PROFILE}" && -r "${PROFILE_CONF}" ]]; then
    PROFILE=$(grep -oP '^AURA_PROFILE=\K.*' "${PROFILE_CONF}" 2>/dev/null || echo "")
  fi
  [[ -n "${PROFILE}" ]] || PROFILE="mid"
  if [[ -z "${FLOOR}" && -r "${PROFILE_CONF}" ]]; then
    FLOOR=$(grep -oP '^FPS_FLOOR=\K.*' "${PROFILE_CONF}" 2>/dev/null || echo "")
  fi
  if [[ -z "${FLOOR}" ]]; then
    case "${PROFILE}" in
      merguez) FLOOR=30 ;;
      high)    FLOOR=60 ;;
      *)       FLOOR=45 ;;
    esac
  fi
  return 0
}

# =============================================================================
# MOTEUR STATISTIQUE — lit des frametimes (ms) TRIÉS CROISSANT sur stdin
#   sort | awk : portable (pas de dépendance gawk/asort)
#   sortie : lignes KEY=VALUE
# =============================================================================
analyse_times() {
  sort -n | awk '
    function ceil(x) { return (x == int(x)) ? x : int(x) + 1 }
    { n++; ft[n] = $1; sum += $1 }
    END {
      if (n == 0) { print "ERROR=trace vide"; exit 1 }
      k1  = ceil(n * 0.01);  if (k1  < 1) k1  = 1
      k01 = ceil(n * 0.001); if (k01 < 1) k01 = 1
      p   = ceil(n * 0.01)                 # indice pour P1 FPS

      # 1% low et 0.1% low : moyenne des FPS des images les plus lentes
      s = 0; for (i = n - k1  + 1; i <= n; i++) s += 1000 / ft[i]; low1  = s / k1
      s = 0; for (i = n - k01 + 1; i <= n; i++) s += 1000 / ft[i]; low01 = s / k01

      med_ms = (n % 2 == 1) ? ft[(n + 1) / 2] : (ft[n / 2] + ft[n / 2 + 1]) / 2
      p1_fps = 1000 / ft[n - p + 1]        # p-ième plus petit FPS (ft décroissant en FPS)
      p99_ms = ft[ceil(n * 0.99)]

      stut = 0
      for (i = 1; i <= n; i++) if (ft[i] > 2 * med_ms && ft[i] > 50) stut++

      printf "frames=%d\n", n
      printf "duration_s=%.3f\n", sum / 1000
      printf "avg_fps=%.2f\n", (1000 * n) / sum
      printf "median_fps=%.2f\n", 1000 / med_ms
      printf "one_pct_low_fps=%.2f\n", low1
      printf "point_one_pct_low_fps=%.2f\n", low01
      printf "p1_fps=%.2f\n", p1_fps
      printf "p99_frame_ms=%.2f\n", p99_ms
      printf "worst_frame_ms=%.2f\n", ft[n]
      printf "stutters=%d\n", stut
    }'
}

# --- Extraction d'une trace → frametimes (ms), un par ligne ------------------
#   auto-détection : colonne "frametime" | colonne "fps" | valeurs nues
parse_trace() {
  local file="$1"
  [[ -r "${file}" ]] || die "trace illisible : ${file}"
  awk '
    BEGIN { FS = "[;, \t]+" }
    /^[[:space:]]*#/ { next }
    NR == 1 && $0 ~ /[A-Za-z]/ {
      for (i = 1; i <= NF; i++) {
        f = tolower($i)
        gsub(/^[ \t"]+|[ \t"]+$/, "", f)
        if (f ~ /frametime/) cft = i
        else if (f ~ /^fps/) cfps = i
      }
      if (cft == 0 && cfps == 0) next   # en-tête sans colonne utile
      next
    }
    {
      if (cft != 0)  { v = $cft;  if (v + 0 > 0) print v; next }
      if (cfps != 0) { v = $cfps; if (v + 0 > 0) printf "%.6f\n", 1000 / v; next }
      for (i = 1; i <= NF; i++) { if ($i + 0 > 0 && $i ~ /^[0-9.]+$/) { print $i; next } }
    }' "${file}"
}

# =============================================================================
# analyse : trace → métriques → verdict → JSON
# =============================================================================
cmd_analyse() {
  [[ -n "${INPUT}" ]] || die "analyse : --input TRACE requis"
  resolve_profile

  local tmp metrics
  tmp=$(mktemp)
  parse_trace "${INPUT}" > "${tmp}"
  [[ -s "${tmp}" ]] || { rm -f "${tmp}"; die "aucune donnée exploitable dans ${INPUT}"; }
  metrics=$(analyse_times < "${tmp}")
  rm -f "${tmp}"

  # Récupération des métriques
  local frames duration avg med low1 low01 p1 p99 worst stutters
  frames=$(grep -oP '^frames=\K.*' <<<"${metrics}")
  duration=$(grep -oP '^duration_s=\K.*' <<<"${metrics}")
  avg=$(grep -oP '^avg_fps=\K.*' <<<"${metrics}")
  med=$(grep -oP '^median_fps=\K.*' <<<"${metrics}")
  low1=$(grep -oP '^one_pct_low_fps=\K.*' <<<"${metrics}")
  low01=$(grep -oP '^point_one_pct_low_fps=\K.*' <<<"${metrics}")
  p1=$(grep -oP '^p1_fps=\K.*' <<<"${metrics}")
  p99=$(grep -oP '^p99_frame_ms=\K.*' <<<"${metrics}")
  worst=$(grep -oP '^worst_frame_ms=\K.*' <<<"${metrics}")
  stutters=$(grep -oP '^stutters=\K.*' <<<"${metrics}")

  # Verdict : le contrat porte sur le 1% low (plancher strict)
  local verdict rc=0
  if awk -v a="${low1}" -v f="${FLOOR}" 'BEGIN { exit !(a + 0 >= f + 0) }'; then
    verdict="PASS"
  else
    verdict="FAIL"; rc=10
  fi

  [[ -n "${GAME}" ]] || GAME=$(basename "${INPUT}")
  local ts json
  ts=$(date -u +%FT%TZ)
  json=$(printf '{"game":"%s","profile":"%s","floor_fps":%s,"frames":%s,"duration_s":%s,"avg_fps":%s,"median_fps":%s,"one_pct_low_fps":%s,"point_one_pct_low_fps":%s,"p1_fps":%s,"p99_frame_ms":%s,"worst_frame_ms":%s,"stutters":%s,"verdict":"%s","timestamp":"%s"}' \
    "${GAME}" "${PROFILE}" "${FLOOR}" "${frames}" "${duration}" "${avg}" "${med}" \
    "${low1}" "${low01}" "${p1}" "${p99}" "${worst}" "${stutters}" "${verdict}" "${ts}")

  # Rapport humain
  echo "════════════════════════════════════════════════════════════"
  echo "  BENCH-FPS — ${GAME}  (profil ${PROFILE}, plancher ${FLOOR} FPS)"
  echo "════════════════════════════════════════════════════════════"
  printf '  images          : %s sur %s s\n' "${frames}" "${duration}"
  printf '  FPS moyen       : %s\n' "${avg}"
  printf '  FPS médian      : %s\n' "${med}"
  printf '  ★ 1%% low        : %s FPS\n' "${low1}"
  printf '  ★ 0.1%% low      : %s FPS\n' "${low01}"
  printf '  P1 FPS          : %s\n' "${p1}"
  printf '  P99 frametime   : %s ms  (pire : %s ms)\n' "${p99}" "${worst}"
  printf '  stutters        : %s images > 2× médiane et > 50 ms\n' "${stutters}"
  echo "────────────────────────────────────────────────────────────"
  if [[ "${verdict}" == "PASS" ]]; then
    printf '  VERDICT         : ✅ PASS — plancher %s FPS tenu (1%% low = %s)\n' "${FLOOR}" "${low1}"
  else
    printf '  VERDICT         : ❌ FAIL — plancher %s FPS NON tenu (1%% low = %s)\n' "${FLOOR}" "${low1}"
  fi
  echo "════════════════════════════════════════════════════════════"

  # Persistance (registre + sortie demandée)
  mkdir -p "${BENCH_DIR}" 2>/dev/null || true
  printf '%s\n' "${json}" >> "${RESULTS}" 2>/dev/null \
    || log "avertissement : registre ${RESULTS} non inscriptible"
  if [[ -n "${OUTPUT}" ]]; then
    printf '%s\n' "${json}" > "${OUTPUT}"
    log "JSON écrit : ${OUTPUT}"
  fi
  if (( MARK )) && [[ "${verdict}" == "PASS" ]]; then
    printf '%s\n' "${json}" >> "${VERIFIED}" 2>/dev/null || true
    log "badge « Verified ${FLOOR} FPS » enregistré pour ${GAME}"
  fi
  return "${rc}"
}

# =============================================================================
# run : lancer un jeu et le mesurer (backend mangohud)
# =============================================================================
cmd_run() {
  (( ${#GAME_CMD[@]} )) || die "run : aucune commande de jeu (usage : ${PROG} run -- <jeu>)"
  [[ -n "${GAME}" ]] || GAME=$(basename "${GAME_CMD[0]}")
  resolve_profile

  case "${BACKEND}" in
    mangohud|auto)
      command -v mangohud >/dev/null 2>&1 \
        || die "mangohud introuvable — installer MangoHud, ou exporter une trace et utiliser : ${PROG} analyse --input trace.csv" ;;
    *) die "backend inconnu : ${BACKEND}" ;;
  esac

  local dir
  dir=$(mktemp -d)
  log "mesure de « ${GAME} » (durée cible : ${DURATION} s, plancher ${FLOOR} FPS)…"
  log "trace MangoHud : ${dir}"

  # MangoHud journalise les frametimes dans un CSV ; la commande du jeu est lancée telle quelle
  MANGOHUD_CONFIG="log_interval=0,log_file=bench.csv,output_folder=${dir}" \
    mangohud "${GAME_CMD[@]}" || log "fin du jeu (code $?)"

  local trace
  trace=$(find "${dir}" -name '*.csv' | head -n1)
  [[ -n "${trace}" && -s "${trace}" ]] || die "aucune trace produite par MangoHud dans ${dir}"
  INPUT="${trace}"
  cmd_analyse
}

# =============================================================================
# report : agrégation du registre + badges
# =============================================================================
cmd_report() {
  if [[ ! -s "${RESULTS}" ]]; then
    log "aucun résultat dans ${RESULTS} — lancez d'abord '${PROG} run' ou '${PROG} analyse'"
    return 0
  fi
  echo "════════════════════════════════════════════════════════════"
  echo "  RAPPORT BENCH — ${RESULTS}"
  echo "════════════════════════════════════════════════════════════"
  printf '  %-22s %-8s %-9s %-9s %-7s %s\n' "JEU" "PROFIL" "MOYEN" "1% LOW" "BADGE" "DERNIER VERDICT"
  # Meilleur 1% low par jeu + dernier verdict
  awk -F'"' '
    {
      # JSON séparé par des guillemets : les chaines (game/profile/verdict)
      # sont en $(i+2) ; les nombres non quotés sont dans $(i+1) avec les
      # deux-points et la virgule autour : nettoyage obligatoire.
      g = ""; p = ""; lo = 0; v = ""; av = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "game" || $i == "profile" || $i == "verdict") {
          val = $(i + 2); gsub(/,$/, "", val)
          if ($i == "game") g = val
          else if ($i == "profile") p = val
          else v = val
        } else if ($i == "one_pct_low_fps" || $i == "avg_fps") {
          val = $(i + 1); gsub(/^:/, "", val); gsub(/,$/, "", val)
          if ($i == "one_pct_low_fps") lo = val + 0
          else av = val + 0
        }
      }
      if (lo > best[g]) best[g] = lo
      avg[g] = av; prof[g] = p; verd[g] = v
    }
    END {
      for (g in best) {
        badge = (best[g] >= 30) ? "V30 ✓" : "—"
        if (best[g] >= 60) badge = "V60 ✓"
        printf "  %-22s %-8s %-9.1f %-9.1f %-7s %s\n", g, prof[g], avg[g], best[g], badge, verd[g]
      }
    }' "${RESULTS}" | sort
  echo "════════════════════════════════════════════════════════════"
  return 0
}

# =============================================================================
# self-test : le moteur statistique sur une fixture aux valeurs connues
#   fixture : 980 × 10 ms (100 FPS), 15 × 25 ms (40 FPS), 5 × 100 ms (10 FPS)
#   attendu : 1% low = 25.00 · 0.1% low = 10.00 · P1 = 40.00 · médian = 100.00
#             avg = 1000×1000/10675 = 93.68 · stutters = 5
# =============================================================================
cmd_self_test() {
  local fixture metrics
  fixture=$(mktemp)
  {
    for _ in $(seq 1 980); do echo "10"; done
    for _ in $(seq 1 15);  do echo "25"; done
    for _ in $(seq 1 5);   do echo "100"; done
  } > "${fixture}"
  metrics=$(analyse_times < "${fixture}")
  rm -f "${fixture}"

  local fail=0
  check() { # check <clé> <attendu> <tolérance>
    local got want tol
    got=$(grep -oP "^$1=\K.*" <<<"${metrics}")
    want="$2"; tol="$3"
    if awk -v a="${got}" -v b="${want}" -v t="${tol}" 'BEGIN { exit !( (a-b) <= t && (b-a) <= t ) }'; then
      printf '  OK    %-22s = %s\n' "$1" "${got}"
    else
      printf '  ECHEC %-22s = %s (attendu %s ± %s)\n' "$1" "${got}" "${want}" "${tol}"
      fail=1
    fi
    return 0
  }
  echo "=== self-test du moteur statistique (fixture connue) ==="
  check one_pct_low_fps       25.00  0.01
  check point_one_pct_low_fps 10.00  0.01
  check p1_fps                40.00  0.01
  check median_fps           100.00  0.01
  check avg_fps               93.68  0.01
  check stutters                5    0
  check frames              1000     0

  if (( fail )); then die "self-test ÉCHOUÉ — le moteur statistique est incorrect"; fi
  echo "=== SELF-TEST OK — moteur statistique conforme ==="
  return 0
}

# =============================================================================
usage() {
  cat <<EOF
usage : ${PROG} <commande> [options]

commandes :
  run -- <jeu...>          mesure une session (backend mangohud)
  analyse --input TRACE    analyse une trace frametimes (CSV ou 1 valeur/ligne)
  report                   agrège les résultats + badges "Verified 30 FPS"
  self-test                vérifie le moteur statistique (fixture connue)

options :
  --game NOM        nom du jeu (défaut : nom du binaire/fichier)
  --profile P       merguez | mid | high (défaut : profil actif)
  --floor N         seuil 1% low explicite (défaut : 30/45/60 selon profil)
  --duration N      durée de mesure en secondes (défaut : 120)
  --input FILE      trace à analyser
  --output FILE     écrit le rapport JSON dans FILE
  --mark-verified   enregistre le badge si le plancher est tenu

exit : 0 = plancher tenu · 10 = plancher NON tenu · 20 = erreur
EOF
}

main() {
  local cmd="${1:-help}"; shift || true
  local args=()
  while (( $# )); do
    case "$1" in
      --game)     GAME="${2:-}"; shift ;;
      --game=*)   GAME="${1#*=}" ;;
      --profile)  PROFILE="${2:-}"; shift ;;
      --profile=*) PROFILE="${1#*=}" ;;
      --floor)    FLOOR="${2:-}"; shift ;;
      --floor=*)  FLOOR="${1#*=}" ;;
      --duration) DURATION="${2:-}"; shift ;;
      --duration=*) DURATION="${1#*=}" ;;
      --backend)  BACKEND="${2:-}"; shift ;;
      --backend=*) BACKEND="${1#*=}" ;;
      --input)    INPUT="${2:-}"; shift ;;
      --input=*)  INPUT="${1#*=}" ;;
      --output)   OUTPUT="${2:-}"; shift ;;
      --output=*) OUTPUT="${1#*=}" ;;
      --mark-verified) MARK=1 ;;
      --)         shift; GAME_CMD+=("$@"); break ;;
      -h|--help)  usage; return 0 ;;
      *)          args+=("$1") ;;
    esac
    shift
  done
  set -- ${args[@]+"${args[@]}"}

  case "${cmd}" in
    run)     cmd_run ;;
    analyse) cmd_analyse ;;
    report)  cmd_report ;;
    self-test|selftest) cmd_self_test ;;
    -h|--help|help) usage ;;
    *) usage; die "commande inconnue : ${cmd}" ;;
  esac
}

main "$@"
