#!/bin/bash
# =============================================================================
# check_stack.sh — vérification de bout en bout des composants DÉMARRÉS
# À exécuter DEPUIS LA MACHINE HÔTE, une fois "docker compose ... up -d" terminé
# (comptez 3 à 5 minutes après le démarrage pour le profil full) :
#   bash scripts/check_stack.sh
# Chaque composant non démarré (profil non activé) est simplement ignoré.
# =============================================================================
set -u

OK=0; KO=0; SKIP=0
LOG="$(mktemp)"
trap 'rm -f "${LOG}"' EXIT

running () { docker ps --format '{{.Names}}' | grep -qx "$1"; }

check () {
  local label="$1"; shift
  if "$@" > "${LOG}" 2>&1; then
    printf "  [ OK ]  %s\n" "${label}"; OK=$((OK + 1))
  else
    printf "  [ KO ]  %s\n" "${label}"; KO=$((KO + 1))
    tail -n 8 "${LOG}" | sed 's/^/           | /'
  fi
}

skip () { printf "  [ -- ]  %s (non démarré)\n" "$1"; SKIP=$((SKIP + 1)); }

echo "== Atelier Hadoop / Hive (socle) =="
check "HDFS : NameNode hors safe mode" \
  bash -c "docker exec namenode hdfs dfsadmin -safemode get | grep -q 'Safe mode is OFF'"
check "YARN : NodeManager enregistré" \
  bash -c "docker exec resourcemanager yarn node -list 2>/dev/null | grep -q RUNNING"
check "Tez : tarball présent sur HDFS" \
  docker exec namenode hdfs dfs -test -f /apps/tez/tez.tar.gz
check "lab-init : données de démonstration chargées (code retour 0)" \
  bash -c "[ \"\$(docker inspect -f '{{.State.ExitCode}}' lab-init 2>/dev/null)\" = 0 ]"
check "Hive : SELECT COUNT(*) FROM sales_db.transactions = 150" \
  bash -c "docker exec hiveserver2 beeline -u 'jdbc:hive2://localhost:10000/default' --silent=true --showHeader=false --outputformat=tsv2 -e 'SELECT COUNT(*) FROM sales_db.transactions' 2>/dev/null | grep -qx 150"

echo ""
echo "== Spark =="
if running spark-master; then
  check "Spark : 1 worker enregistré auprès du master" \
    bash -c "docker exec spark-master curl -fs http://localhost:8080/json/ | grep -q '\"aliveworkers\" *: *1'"
  check "Spark : lecture de sales_db.transactions via le metastore Hive (spark-submit)" \
    bash -c "docker exec spark-master spark-submit /opt/scripts/spark/smoke_test.py 2>&1 | grep 'SPARK_OK' | grep -q 'transactions=150'"
else skip "Spark"; fi
if running spark-history; then
  check "Spark History Server (port 18080)" \
    docker exec spark-history curl -fs http://localhost:18080/api/v1/applications
else skip "Spark History Server"; fi

echo ""
echo "== Zeppelin =="
if running zeppelin; then
  check "Zeppelin : API REST (port 8082)" \
    docker exec zeppelin curl -fs http://localhost:8082/api/version
  check "Zeppelin : interpréteurs spark, hive, impala, sh, python déclarés" \
    bash -c "docker exec zeppelin curl -fs http://localhost:8082/api/interpreter/setting | python3 -c 'import json,sys; names={s[\"name\"] for s in json.load(sys.stdin)[\"body\"]}; missing={\"spark\",\"hive\",\"impala\",\"sh\",\"python\",\"md\"}-names; print(\"manquants:\", missing); sys.exit(1 if missing else 0)'"
  check "Zeppelin : client HDFS disponible pour %sh" \
    docker exec zeppelin hdfs dfs -ls /user/data
else skip "Zeppelin"; fi

echo ""
echo "== HBase =="
if running hbase-master; then
  check "HBase : master actif + RegionServer en ligne" \
    bash -c "echo status | docker exec -i hbase-master hbase shell -n 2>/dev/null | grep -Eq '1 active master.*[1-9][0-9]* servers'"
  check "HBase : table de démonstration clients_hbase (20 lignes)" \
    bash -c "echo \"count 'clients_hbase'\" | docker exec -i hbase-master hbase shell -n 2>/dev/null | grep -q '20 row'"
else skip "HBase"; fi
if running hbase-thrift; then
  check "HBase Thrift (port 9090, utilisé par Hue)" \
    docker exec hbase-thrift bash -c "echo > /dev/tcp/localhost/9090"
else skip "HBase Thrift"; fi

echo ""
echo "== Impala =="
if running impalad; then
  check "Impala : SELECT COUNT(*) FROM sales_db.transactions = 150" \
    bash -c "docker exec hiveserver2 beeline -u 'jdbc:hive2://impalad:21050/default;auth=noSasl' --silent=true --showHeader=false --outputformat=tsv2 -e 'INVALIDATE METADATA sales_db.transactions; SELECT COUNT(*) FROM sales_db.transactions;' 2>/dev/null | grep -qx 150"
else skip "Impala"; fi

echo ""
echo "== Hue =="
if running hue; then
  check "Hue : serveur web (port 8888)" \
    docker exec hue curl -fs http://localhost:8888/desktop/debug/is_alive
else skip "Hue"; fi

echo ""
echo "Résultat : ${OK} OK, ${KO} KO, ${SKIP} non démarré(s)"
[ "${KO}" -eq 0 ]
