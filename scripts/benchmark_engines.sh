#!/bin/bash
# Atelier — Étape 4 : comparaison des moteurs d'exécution Hive
# À exécuter DEPUIS LA MACHINE HÔTE (pas besoin de faire docker exec soi-même) :
#   bash scripts/benchmark_engines.sh
#
# Lance la même requête (COUNT(*) par ville sur la table `clients`) avec
# MapReduce puis Tez, chronomètre chaque exécution, et ajoute LLAP
# automatiquement si le profil bonus est démarré (--profile llap).
#
# Pendant une mesure, un point d'étape s'affiche toutes les 20 s, avec l'état
# YARN si le job attend des ressources. Le chronométrage ne compte pas ces
# contrôles. Les avertissements de journalisation de beeline (SLF4J, Log4j)
# sont masqués.
set -euo pipefail

QUERY="SELECT ville, COUNT(*) AS nb_clients FROM clients GROUP BY ville;"
HS2_MAIN="hiveserver2"
HS2_LLAP="hiveserver2-llap"

# Avertissements sans conséquence affichés par beeline (image Hive 4.1.0)
# shellcheck disable=SC2016  # les backquotes font partie du texte recherché
NOISE_RE='^SLF4J:|The use of package scanning to locate Log4j plugins is deprecated|Please remove the `packages` attribute|logging.apache.org/log4j/2.x/faq.html#package-scanning'
TIMES="$(mktemp)"
trap 'rm -f "${TIMES}"' EXIT

# Applications YARN dans les états donnés (ex. RUNNING,ACCEPTED) : "id  nom  état"
yarn_apps () {
  docker exec resourcemanager yarn application -list -appStates "$1" 2>/dev/null \
    | awk -F'\t' '$1 ~ /application_/ {
        for (i = 1; i <= NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
        printf "  %s  %s  %s\n", $1, $2, $6 }' || true
}

# Exécute "$@" en arrière-plan, journaux parasites masqués. Écrit "début fin"
# dans ${TIMES} et affiche un point d'étape toutes les 20 s.
measure () {
  (
    rc=0
    s=$(date +%s.%N)
    "$@" 2> >(grep -v -E "${NOISE_RE}" >&2) || rc=$?
    e=$(date +%s.%N)
    echo "${s} ${e}" > "${TIMES}"
    exit "${rc}"
  ) < /dev/null &
  local pid=$! t=0 waiting rc=0
  while kill -0 "${pid}" 2>/dev/null; do
    sleep 1
    t=$((t + 1))
    if [ $((t % 20)) -eq 0 ]; then
      waiting=$(yarn_apps ACCEPTED | grep -c . || true)
      if [ "${waiting}" -gt 0 ]; then
        echo "  … ${t} s : ${waiting} application(s) YARN en attente de ressources (ACCEPTED), voir http://localhost:8088" >&2
      else
        echo "  … ${t} s : requête en cours" >&2
      fi
    fi
  done
  wait "${pid}" || rc=$?
  return "${rc}"
}

print_time () {
  awk -v l="$1" '{printf "Temps %-28s : %.1f s\n", l, $2 - $1}' "${TIMES}"
}

run_query () {
  local container="$1" ; local engine_sql="$2" ; local label="$3"
  echo ""
  echo "----- ${label} -----"
  measure docker exec -i "${container}" beeline \
    -u 'jdbc:hive2://localhost:10000/default' \
    --showHeader=true --silent=true \
    -e "${engine_sql} ${QUERY}"
  print_time "${label}"
}

if ! docker ps --format '{{.Names}}' | grep -qx "${HS2_MAIN}"; then
  echo "Le conteneur ${HS2_MAIN} n'est pas démarré (docker compose up -d ?)."
  exit 1
fi

# Applications YARN déjà actives (souvent des sessions Tez laissées ouvertes par
# Hue, Zeppelin ou un beeline) : elles faussent les temps et peuvent faire
# attendre le job MapReduce.
busy="$(yarn_apps RUNNING,ACCEPTED)"
if [ -n "${busy}" ]; then
  echo "ATTENTION : des applications YARN sont déjà actives (sessions Hue, Zeppelin, beeline...)."
  echo "Elles occupent le cluster et faussent les mesures :"
  echo "${busy}"
  echo "Pour les arrêter : docker exec resourcemanager yarn application -kill <Application-Id>"
  echo "(une session Tez inactive s'arrête d'elle-même au bout de 5 minutes)"
fi

run_query "${HS2_MAIN}" "SET hive.execution.engine=mr;"  "MapReduce (mr)"
run_query "${HS2_MAIN}" "SET hive.execution.engine=tez;" "Tez (tez, défaut)"

if docker ps --format '{{.Names}}' | grep -qx "${HS2_LLAP}"; then
  run_query "${HS2_LLAP}" "SET hive.execution.engine=tez; SET hive.llap.execution.mode=all;" "Tez + LLAP (bonus)"
else
  echo ""
  echo "(bonus LLAP non démarré — voir README, section 'Bonus LLAP' :"
  echo " docker compose --profile llap up -d)"
fi

# ── Moteurs ajoutés (optionnels) : mesurés seulement s'ils sont démarrés ──────
time_cmd () {
  local label="$1"; shift
  echo ""
  echo "----- ${label} -----"
  # Un échec sur un moteur bonus ne doit pas interrompre le benchmark
  measure "$@" || echo "  (échec de la mesure '${label}' : voir docker compose logs)"
  print_time "${label}"
}

if docker ps --format '{{.Names}}' | grep -qx "impalad"; then
  # Impala lit la même table "clients" via le metastore partagé (démon toujours
  # actif : pas de démarrage de conteneurs YARN, d'où des temps très courts).
  time_cmd "Impala (bonus)" docker exec -i "${HS2_MAIN}" beeline \
    -u 'jdbc:hive2://impalad:21050/default;auth=noSasl' \
    --showHeader=true --silent=true \
    -e "INVALIDATE METADATA default.clients; ${QUERY}"
else
  echo ""
  echo "(Impala non démarré : docker compose --profile impala up -d)"
fi

if docker ps --format '{{.Names}}' | grep -qx "spark-master"; then
  # Spark SQL : le temps inclut le lancement de l'application Spark (driver + executors)
  # (journaux INFO de Spark envoyés sur stderr : masqués, seul le résultat s'affiche)
  time_cmd "Spark SQL (bonus)" bash -c "docker exec -i spark-master spark-submit \
    --conf spark.ui.showConsoleProgress=false /opt/scripts/spark/query_villes.py 2>/dev/null"
else
  echo ""
  echo "(Spark non démarré : docker compose --profile spark up -d)"
fi

echo ""
echo "Les temps incluent le démarrage de l'Application Master (AM) pour notre test, avec un impact dominant sur un aussi petit jeu de données :"
echo "c'est justement cet écart de démarrage que l'atelier vous fait observer entre MapReduce et Tez."
