#!/bin/bash
# =============================================================================
# init-hbase.sh — service one-shot "hbase-init"
# Attend qu'HBase soit opérationnel puis crée la table de démonstration
# "clients_hbase" si elle n'existe pas encore. Idempotent.
#
#   1. Interface web du master (JMX, curl : rapide) : master actif et au moins
#      un RegionServer enregistré.
#   2. Shell HBase : "status" répond, ce qui suppose le master initialisé et
#      hbase:meta en ligne. Sinon PleaseHoldException « Master is initializing ».
#   3. Création de la table si besoin, puis vérification par "exists".
#
# La sortie du shell est d'abord capturée, puis analysée. L'ancienne version
# faisait « hbase shell | grep -q » sous « set -o pipefail » : grep -q
# s'arrête dès la ligne trouvée, le shell (qui écrit encore « Took ... »)
# échoue alors en écriture, et pipefail retenait cet échec. Résultat : HBase
# n'était JAMAIS détecté prêt, même démarré.
# =============================================================================
set -u

MASTER_UI="${HBASE_MASTER_UI:-http://hbase-master:16010}"
JMX_URL="${MASTER_UI}/jmx?qry=Hadoop:service=HBase,name=Master,sub=Server"
WAIT_RS_TIMEOUT="${WAIT_RS_TIMEOUT:-600}"         # s : master actif + RegionServer
WAIT_SHELL_TIMEOUT="${WAIT_SHELL_TIMEOUT:-300}"   # s : master initialisé
POLL_JMX="${POLL_JMX:-5}"
POLL_SHELL="${POLL_SHELL:-10}"
DEMO_SCRIPT="${DEMO_SCRIPT:-/opt/hbase-scripts/demo_clients.hbase}"

STATUS_RE='1 active master, [0-9]+ backup masters, [1-9][0-9]* servers'
LAST_SHELL_OUTPUT=""

# Valeur d'un attribut du JSON JMX (nombre ou chaîne entre guillemets)
jmx_value () {
  printf '%s' "$1" | tr -d '\n' \
    | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",} ]*\)\"\{0,1\}.*/\1/p"
}

# Sortie du shell sans les avertissements de journalisation sans intérêt
clean () { printf '%s\n' "$1" | grep -v -E '^SLF4J:|^\s*$' ; }

diagnostic () {
  echo "---------------------------------------------------------------- diagnostic"
  local json
  json="$(curl -fsS --max-time 5 "${JMX_URL}" 2>/dev/null || true)"
  if [ -n "${json}" ]; then
    echo "Master (${MASTER_UI}) : actif=$(jmx_value "${json}" 'tag.isActiveMaster')," \
         "RegionServers enregistrés=$(jmx_value "${json}" 'numRegionServers')," \
         "RegionServers morts=$(jmx_value "${json}" 'numDeadRegionServers')"
  else
    echo "Interface du master injoignable : ${MASTER_UI}"
  fi
  if [ -n "${LAST_SHELL_OUTPUT}" ]; then
    echo "Dernière réponse du shell HBase :"
    clean "${LAST_SHELL_OUTPUT}" | tail -n 15 | sed 's/^/  | /'
  fi
  echo "Pistes : docker logs hbase-master 2>&1 | grep -E 'ERROR|WARN' | tail -20"
  echo "         docker logs hbase-regionserver 2>&1 | grep -E 'ERROR|WARN' | tail -20"
  echo "---------------------------------------------------------------------------"
}

fail () { echo "ERREUR : $*"; diagnostic; exit 1; }

echo "================================================================"
echo " hbase-init : attente de la disponibilité d'HBase..."
echo "================================================================"

# ── 1. Master actif + RegionServer enregistré (JMX) ──────────────────────────
deadline=$((SECONDS + WAIT_RS_TIMEOUT))
last_state=""
while :; do
  json="$(curl -fsS --max-time 5 "${JMX_URL}" 2>/dev/null || true)"
  if [ -n "${json}" ]; then
    active="$(jmx_value "${json}" 'tag.isActiveMaster')"
    rs="$(jmx_value "${json}" 'numRegionServers')"
    case "${rs}" in ''|*[!0-9]*) rs_num=0 ;; *) rs_num="${rs}" ;; esac
    if [ "${active}" = "true" ] && [ "${rs_num}" -ge 1 ]; then
      echo "  OK - master actif, ${rs_num} RegionServer(s) enregistré(s)"
      break
    fi
    if [ -z "${active}" ] && [ -z "${rs}" ]; then
      echo "  (métriques JMX du master introuvables : vérification directe par le shell)"
      break
    fi
    state="master actif=${active:-?}, RegionServers enregistrés=${rs:-?}"
  else
    state="interface du master pas encore joignable (${MASTER_UI})"
  fi
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    fail "HBase pas prêt après ${WAIT_RS_TIMEOUT} s (${state})"
  fi
  if [ "${state}" != "${last_state}" ]; then
    echo "  -> en attente : ${state}"
    last_state="${state}"
  fi
  sleep "${POLL_JMX}"
done

# ── 2. Master initialisé : le shell répond à "status" ────────────────────────
deadline=$((SECONDS + WAIT_SHELL_TIMEOUT))
attempt=0
while :; do
  attempt=$((attempt + 1))
  LAST_SHELL_OUTPUT="$(printf "status\nexists 'clients_hbase'\n" | hbase shell -n 2>&1)"
  if [[ ${LAST_SHELL_OUTPUT} =~ ${STATUS_RE} ]]; then
    echo "  OK - HBase opérationnel : ${BASH_REMATCH[0]}"
    break
  fi
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    fail "le master HBase ne répond pas après ${WAIT_SHELL_TIMEOUT} s (initialisation non terminée)"
  fi
  if [[ ${LAST_SHELL_OUTPUT} == *"initializing"* ]]; then
    reason="master en cours d'initialisation (ouverture de hbase:meta)"
  else
    reason="pas de réponse exploitable du shell"
  fi
  echo "  -> ${reason}, essai ${attempt}, nouvel essai dans ${POLL_SHELL} s..."
  sleep "${POLL_SHELL}"
done

# ── 3. Table de démonstration ────────────────────────────────────────────────
if [[ ${LAST_SHELL_OUTPUT} == *"clients_hbase does exist"* ]]; then
  echo "  OK - table clients_hbase déjà présente, rien à faire."
  exit 0
fi

echo "Création de la table de démonstration clients_hbase..."
LAST_SHELL_OUTPUT="$(hbase shell -n "${DEMO_SCRIPT}" < /dev/null 2>&1)"
rc=$?
check="$(printf "exists 'clients_hbase'\n" | hbase shell -n 2>&1)"
if [[ ${check} != *"clients_hbase does exist"* ]]; then
  fail "création de clients_hbase en échec (code ${rc})"
fi
rows="$(clean "${LAST_SHELL_OUTPUT}" | grep -E '^[0-9]+ row\(s\)' | tail -n 1)"
echo "================================================================"
echo " hbase-init : TERMINÉ avec succès (table clients_hbase créée${rows:+, ${rows}})"
echo "================================================================"
