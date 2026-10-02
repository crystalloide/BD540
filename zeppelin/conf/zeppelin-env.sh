#!/bin/bash
# =============================================================================
# Zeppelin 0.12.1 — environnement de l'atelier
# Ce fichier est lu par bin/zeppelin.sh (serveur) ET par bin/interpreter.sh
# (chaque processus d'interpréteur), via bin/common.sh.
# =============================================================================

# ── Deux JDK ──────────────────────────────────────────────────────────────────
#  * serveur Zeppelin : JDK 11, le seul JDK validé par le projet Zeppelin 0.12
#    pour le serveur (sa CI ne teste JDK 17 que pour les interpréteurs Spark) ;
#  * interpréteurs : JDK 17, indispensable pour Spark 4.0 et pour le pilote JDBC
#    Hive 4.1.0 (compilé en bytecode Java 17).
# bin/interpreter.sh définit INTERPRETER_DIR avant de lire ce fichier : c'est ce
# qui distingue un processus d'interpréteur du serveur.
# L'interpréteur %java (qui compile avec javac) reçoit le JDK complet /opt/jdk17
# via la propriété ZEPPELIN_INTERPRETER_JAVA_HOME de son réglage.
if [[ -n "${INTERPRETER_DIR:-}" ]]; then
  export JAVA_HOME="${ZEPPELIN_INTERPRETER_JAVA_HOME:-/opt/java/openjdk}"
else
  export JAVA_HOME="${ZEPPELIN_SERVER_JAVA_HOME:-/opt/jdk11}"
fi

# ── Spark 4.0.4 et client Hadoop 3.4.2 de l'image ────────────────────────────
export SPARK_HOME=/opt/spark
export SPARK_CONF_DIR=/opt/spark/conf
export HADOOP_CONF_DIR=/opt/hadoop-conf
export PYSPARK_PYTHON=python3
export PYSPARK_DRIVER_PYTHON=python3

# Client HBase 2.6.7 (interpréteur %hbase : "$HBASE_HOME/bin/hbase shell")
export HBASE_HOME=/opt/hbase

# IMPORTANT : sans USE_HADOOP=false, bin/zeppelin.sh ajoute "hadoop classpath"
# (Hadoop 3.4.2 complet : Jetty 9, Guava, Jackson...) au classpath du SERVEUR
# Zeppelin dès que la commande "hadoop" est dans le PATH -> conflits de jars.
# Le serveur n'a pas besoin de Hadoop (notebooks stockés localement).
export USE_HADOOP=false

# ── Mémoire ───────────────────────────────────────────────────────────────────
export ZEPPELIN_MEM="-Xms256m -Xmx1024m"
# Interpréteurs JDBC (%hive, %impala), %sh, %python. Le driver Spark, lui, est
# dimensionné par spark.driver.memory (interpréteur spark).
export ZEPPELIN_INTP_MEM="-Xms128m -Xmx512m"
