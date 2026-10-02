#!/bin/bash
# =============================================================================
# lab-init.sh — données de démonstration (service one-shot "lab-init")
# Tourne dans l'image Hive (atelier-hive-tez/hive-fixed:4.1.0) une fois
# HiveServer2 "healthy" : dépose data/transactions.csv sur HDFS puis crée
# sales_db.transactions (base utilisée par le TP Zeppelin N1).
# Idempotent : relancé à chaque "docker compose up", sans effet de bord.
# =============================================================================
set -euo pipefail

export HADOOP_CONF_DIR=/hive_custom_conf
# Même mécanisme que l'entrypoint officiel de l'image (remplacé par ce script) :
# les fichiers de hive-conf/ sont liés dans le répertoire de configuration de
# Hive, dont beeline-log4j2.properties (pas d'avertissement Log4j « package scanning »).
export HIVE_CONF_DIR="${HIVE_HOME:-/opt/hive}/conf"
find /hive_custom_conf -type f -exec ln -sfn {} "${HIVE_CONF_DIR}/" \; \
  || echo "(liens vers hive-conf/ non créés : seul l'avertissement Log4j réapparaît)"
HDFS_DIR=/user/hadoop/demo/transactions
JDBC_URL="jdbc:hive2://hiveserver2:10000/default"

echo "================================================================"
echo " lab-init : chargement des données de démonstration (sales_db)"
echo "================================================================"

hdfs dfs -mkdir -p "${HDFS_DIR}"
hdfs dfs -put -f /opt/data/transactions.csv "${HDFS_DIR}/transactions.csv"
hdfs dfs -chmod -R 777 /user/hadoop/demo
hdfs dfs -ls "${HDFS_DIR}"

# HiveServer2 est déclaré "healthy" dès que son port répond ; on laisse
# quelques tentatives au cas où la première session serait refusée.
for i in 1 2 3 4 5 6; do
  if beeline -u "${JDBC_URL}" -n hive --silent=true --showHeader=true \
       -f /opt/scripts/00_demo_sales_db.hql; then
    echo ""
    echo "================================================================"
    echo " lab-init : TERMINÉ avec succès (sales_db.transactions prête)"
    echo "================================================================"
    exit 0
  fi
  echo "  -> HiveServer2 pas encore prêt, nouvelle tentative dans 10s (${i}/6)..."
  sleep 10
done

echo "ERREUR : impossible de créer sales_db via HiveServer2 (voir les logs ci-dessus)"
exit 1
