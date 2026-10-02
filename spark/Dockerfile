# =============================================================================
# Images "Spark 4.0.4" et "Zeppelin 0.12.1" de l'atelier (un seul Dockerfile,
# deux cibles) :
#   docker build -f spark/Dockerfile --target spark    .   -> spark-master/worker/history
#   docker build -f spark/Dockerfile --target zeppelin .   -> zeppelin
# (le contexte de build est la RACINE du projet : voir docker-compose.yml)
#
# Pourquoi ces versions (détails dans le README, section "Notes techniques") :
#  * Hive 4.1.0 (metastore du cluster) a SUPPRIMÉ l'appel Thrift "get_table"
#    utilisé par le client Hive 2.3 intégré à Spark : aucun Spark 3.x ne peut
#    lire le catalogue Hive de ce cluster avec sa configuration par défaut.
#    Spark 4.0.x sait charger un client metastore Hive 4.0 isolé
#    (spark.sql.hive.metastore.version=4.0.1, SPARK-45265) : c'est ce client
#    qu'on embarque ci-dessous.
#  * Zeppelin 0.12.1 supporte officiellement Spark 4.0 (ZEPPELIN-6086) mais pas
#    encore Spark 4.1 -> Spark 4.0.4 (dernier correctif de la branche 4.0).
#  * JDK 17 partout, comme le cluster Hadoop/Hive de l'atelier.
# =============================================================================

ARG SPARK_IMAGE=apache/spark:4.0.4-scala2.13-java17-python3-ubuntu
ARG HADOOP_IMAGE=apache/hadoop:3.4.2
ARG HIVE_METASTORE_CLIENT_IMAGE=apache/hive:4.0.1
ARG MAVEN_IMAGE=maven:3.9-eclipse-temurin-17
ARG JDK_IMAGE=eclipse-temurin:17-jdk-jammy
ARG HBASE_VERSION=2.6.7

# -----------------------------------------------------------------------------
# Client Hadoop 3.4.2 (MÊME image que le cluster : rien de plus à télécharger).
# Sert uniquement aux commandes "hdfs dfs ..." / "yarn ..." (ex. %sh dans
# Zeppelin). Spark, lui, utilise ses propres jars clients Hadoop.
# On retire la documentation et share/hadoop/tools (~600 Mo de SDK cloud).
# -----------------------------------------------------------------------------
FROM ${HADOOP_IMAGE} AS hadoop-dist
USER root
RUN rm -rf /opt/hadoop/share/doc /opt/hadoop/share/hadoop/tools

# -----------------------------------------------------------------------------
# Jars du client metastore Hive 4.0.1, pris dans l'image officielle Apache Hive
# 4.0.1 (déterministe : aucune résolution de dépendances Maven au build).
# Spark exige des jars de la version déclarée dans
# spark.sql.hive.metastore.version ; 4.0.1 est la version la plus récente
# supportée par Spark 4.0 et son protocole Thrift est un sous-ensemble strict de
# celui du metastore 4.1.0 du cluster (vérifié sur les fichiers .thrift).
# -----------------------------------------------------------------------------
FROM ${HIVE_METASTORE_CLIENT_IMAGE} AS hive-metastore-client

# -----------------------------------------------------------------------------
# Dépendances Maven de Zeppelin :
#  * interpréteur %sh : RETIRÉ des binaires officiels de Zeppelin depuis 0.11.1
#    ("[HOTFIX] Disable shell interpreter"), mais toujours publié sur Maven
#    Central (org.apache.zeppelin:zeppelin-shell:0.12.1) ;
#  * pilote JDBC Hive 4.1.0 "standalone" (MÊME version que HiveServer2), utilisé
#    par les interpréteurs %hive et %impala.
# -----------------------------------------------------------------------------
FROM ${MAVEN_IMAGE} AS zeppelin-maven-deps
WORKDIR /build
COPY zeppelin/maven/pom.xml /build/pom.xml
RUN mvn -B -ntp -f /build/pom.xml \
        org.apache.maven.plugins:maven-dependency-plugin:3.6.1:copy-dependencies \
        -DincludeScope=runtime -DoutputDirectory=/build/sh \
 && mvn -B -ntp -f /build/pom.xml \
        org.apache.maven.plugins:maven-dependency-plugin:3.6.1:copy \
        -Dartifact=org.apache.hive:hive-jdbc:4.1.0:jar:standalone -DoutputDirectory=/build/jdbc \
 && ls -l /build/sh /build/jdbc \
 && test -f /build/sh/zeppelin-shell-0.12.1.jar \
 && test -f /build/jdbc/hive-jdbc-4.1.0-standalone.jar

# -----------------------------------------------------------------------------
# JDK 17 complet pour l'interpréteur %java de Zeppelin : il compile le code des
# paragraphes avec javac (javax.tools), absent du JRE de l'image Spark. Les
# autres interpréteurs gardent ce JRE. jmods et sources retirés (inutiles).
# -----------------------------------------------------------------------------
FROM ${JDK_IMAGE} AS jdk17
RUN rm -rf /opt/java/openjdk/jmods /opt/java/openjdk/lib/src.zip \
 && /opt/java/openjdk/bin/javac -version

# =============================================================================
# Cible "spark" : Spark 4.0.4 (Scala 2.13, JDK 17, Python 3.10)
# =============================================================================
FROM ${SPARK_IMAGE} AS spark
USER root

# python-is-python3 : la commande "python" (valeur par défaut de plusieurs
# réglages PySpark/Zeppelin) pointe vers python3.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python-is-python3 curl ca-certificates netcat-openbsd procps; \
    rm -rf /var/lib/apt/lists/*

COPY --from=hadoop-dist /opt/hadoop /opt/hadoop

# Client metastore Hive 4.0.1 + les quelques jars Hadoop que Spark ajoute
# lui-même à ce client en mode "maven" (hadoop-hdfs 3.3.6, cf. HiveVersion v4_0
# dans le code de Spark) et les bibliothèques relocalisées dont ils dépendent.
COPY --from=hive-metastore-client /opt/hive/lib/ /opt/hive-metastore-4.0.1/lib/
COPY --from=hive-metastore-client /opt/hadoop/share/hadoop/hdfs/hadoop-hdfs-3*.jar /opt/hive-metastore-4.0.1/lib/
COPY --from=hive-metastore-client /opt/hadoop/share/hadoop/common/lib/hadoop-shaded-*.jar /opt/hive-metastore-4.0.1/lib/

# Configuration Spark (spark-defaults.conf, hive-site.xml) et client Hadoop
COPY spark/conf/ /opt/spark/conf/
COPY spark/hadoop-conf/ /opt/hadoop-conf/

# NB : HADOOP_HOME n'est volontairement PAS défini. L'entrypoint de l'image
# officielle Spark ajouterait alors "hadoop classpath" (Hadoop 3.4.2 complet)
# devant les jars Hadoop déjà embarqués par Spark -> doublons de classes.
# Les scripts /opt/hadoop/bin/* retrouvent leur répertoire tout seuls.
ENV SPARK_HOME=/opt/spark \
    SPARK_CONF_DIR=/opt/spark/conf \
    HADOOP_CONF_DIR=/opt/hadoop-conf \
    PYSPARK_PYTHON=python3 \
    PYSPARK_DRIVER_PYTHON=python3 \
    PATH=/opt/spark/bin:/opt/spark/sbin:/opt/hadoop/bin:${PATH}

RUN set -eux; \
    test -f /opt/hive-metastore-4.0.1/lib/hive-metastore-4.0.1.jar; \
    test -f /opt/hive-metastore-4.0.1/lib/hive-exec-4.0.1.jar; \
    ls /opt/hive-metastore-4.0.1/lib/hadoop-hdfs-3*.jar; \
    mkdir -p /opt/spark/work /opt/spark/logs /opt/scripts; \
    chown -R spark:spark /opt/spark/conf /opt/spark/work /opt/spark/logs; \
    /opt/hadoop/bin/hadoop version | head -1; \
    python3 --version; \
    java -version

WORKDIR /opt/spark/work-dir
USER spark

# -----------------------------------------------------------------------------
# Client HBase 2.6.7 (même version que le cluster) pour l'interpréteur %hbase :
# Zeppelin 0.12.1 exécute "$HBASE_HOME/bin/hbase shell <paragraphe>".
# Téléchargement Apache avec repli sur archive.apache.org.
# -----------------------------------------------------------------------------
FROM spark AS hbase-client
USER root
ARG HBASE_VERSION
RUN set -eux; \
    f="hbase-${HBASE_VERSION}-hadoop3-bin.tar.gz"; \
    for url in "https://dlcdn.apache.org/hbase/${HBASE_VERSION}/${f}" \
               "https://archive.apache.org/dist/hbase/${HBASE_VERSION}/${f}"; do \
        curl -fSL --retry 3 -o "/tmp/${f}" "${url}" && break; \
    done; \
    test -s "/tmp/${f}"; \
    mkdir -p /opt/hbase; \
    tar -xzf "/tmp/${f}" -C /opt/hbase --strip-components=1; \
    rm -rf "/tmp/${f}" /opt/hbase/docs; \
    test -x /opt/hbase/bin/hbase; \
    test -d /opt/hbase/lib/ruby

# =============================================================================
# Cible "zeppelin" : Zeppelin 0.12.1 construit SUR l'image Spark ci-dessus
# (même Spark, même Python 3.10 que les workers : obligatoire pour PySpark).
#  * serveur Zeppelin : JDK 11 (seul JDK validé par le projet Zeppelin 0.12) ;
#  * interpréteurs : JRE 17 (Spark 4 l'exige, le pilote JDBC Hive 4.1.0 est
#    compilé pour Java 17), JDK 17 complet pour %java -> voir conf/zeppelin-env.sh
#  * TOUS les interpréteurs de la distribution "bin-all" sont conservés, plus
#    %sh (Maven). Ceux qui ont besoin d'un service absent de l'atelier
#    (Cassandra, MongoDB, Flink, Livy...) apparaissent mais ne s'exécutent pas
#    sans ce service : voir le README, section Zeppelin.
# =============================================================================
FROM spark AS zeppelin
USER root

ARG ZEPPELIN_VERSION=0.12.1
ARG HBASE_VERSION

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openjdk-11-jre-headless tini python3-setuptools; \
    rm -rf /var/lib/apt/lists/*; \
    ln -s "/usr/lib/jvm/java-11-openjdk-$(dpkg --print-architecture)" /opt/jdk11; \
    /opt/jdk11/bin/java -version

# Binaire officiel "bin-all" (spark, jdbc, python, md...). dlcdn ne garde que la
# dernière version publiée : repli automatique sur archive.apache.org.
RUN set -eux; \
    f="zeppelin-${ZEPPELIN_VERSION}-bin-all.tgz"; \
    for url in "https://dlcdn.apache.org/zeppelin/zeppelin-${ZEPPELIN_VERSION}/${f}" \
               "https://archive.apache.org/dist/zeppelin/zeppelin-${ZEPPELIN_VERSION}/${f}"; do \
        curl -fSL --retry 3 -o "/tmp/${f}" "${url}" && break; \
    done; \
    test -s "/tmp/${f}"; \
    mkdir -p /opt/zeppelin; \
    tar -xzf "/tmp/${f}" -C /opt/zeppelin --strip-components=1; \
    rm -f "/tmp/${f}"; \
    # Tous les interpréteurs sont conservés. Seuls les notebooks d'exemple qui
    # ne peuvent pas fonctionner ici sont retirés (Flink, R, Mahout, Keras...).
    cd /opt/zeppelin/notebook; \
    rm -rf "Flink Tutorial" "R Tutorial" "Miscellaneous Tutorial" "Python Tutorial"; \
    rm -f "Spark Tutorial/5. SparkR Basics_2BWJFTXKM.zpln" \
          "Spark Tutorial/6. SparkR Shiny App_2F1CHQ4TT.zpln" \
          "Spark Tutorial/7. Spark Delta Lake Tutorial_2F8VDBMMT.zpln" \
          "Spark Tutorial/8. PySpark Conda Env in Yarn Mode_2GE79Y5FV.zpln"; \
    ls /opt/zeppelin/interpreter

# Interpréteur %sh (zeppelin-shell 0.12.1 + dépendances) et pilote JDBC Hive 4.1.0
COPY --from=zeppelin-maven-deps /build/sh/ /opt/zeppelin/interpreter/sh/
COPY --from=zeppelin-maven-deps /build/jdbc/hive-jdbc-4.1.0-standalone.jar /opt/zeppelin/interpreter/jdbc/
# interpreter-setting.json est extrait du jar zeppelin-shell, en ne gardant que
# %sh (voir zeppelin/build/keep_sh_interpreter.py pour le pourquoi).
COPY zeppelin/build/keep_sh_interpreter.py /tmp/keep_sh_interpreter.py
RUN python3 /tmp/keep_sh_interpreter.py \
        "/opt/zeppelin/interpreter/sh/zeppelin-shell-${ZEPPELIN_VERSION}.jar" \
        /opt/zeppelin/interpreter/sh/interpreter-setting.json \
 && rm -f /tmp/keep_sh_interpreter.py
RUN set -eux; \
    ls /opt/zeppelin/interpreter/zeppelin-interpreter-shaded-*.jar; \
    ls /opt/zeppelin/interpreter/spark/scala-2.13/; \
    ls /opt/zeppelin/interpreter/jdbc/ /opt/zeppelin/interpreter/sh/; \
    for i in alluxio angular bigquery cassandra elasticsearch file flink flink-cmd \
             groovy hbase influxdb java jdbc jupyter livy md mongodb neo4j python \
             r sh spark spark-submit sparql; do \
        test -d "/opt/zeppelin/interpreter/${i}" || { echo "interpréteur absent : ${i}"; exit 1; }; \
    done

# %java : JDK 17 complet (javac). Choisi par ZEPPELIN_INTERPRETER_JAVA_HOME dans
# le réglage de l'interpréteur java (conf/interpreter.json).
COPY --from=jdk17 /opt/java/openjdk /opt/jdk17

# %hbase : client HBase 2.6.7 relié au ZooKeeper de l'atelier. HBase ne doit
# pas ajouter "hadoop classpath" (Hadoop 3.4.2 de l'image, dans le PATH) à ses
# propres jars client.
COPY --from=hbase-client /opt/hbase /opt/hbase
COPY zeppelin/hbase-conf/hbase-site.xml /opt/hbase/conf/hbase-site.xml
RUN set -eux; \
    { echo ''; \
      echo '# --- Atelier : client HBase de Zeppelin (interpréteur %hbase) ---'; \
      echo 'export HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP="true"'; \
      echo 'export HBASE_MANAGES_ZK=false'; \
      echo 'export HBASE_HEAPSIZE=512m'; \
      echo 'export HBASE_LOG_DIR=/tmp/hbase-logs'; } >> /opt/hbase/conf/hbase-env.sh; \
    case "$(/opt/hbase/bin/hbase version 2>&1)" in \
      *"HBase ${HBASE_VERSION:-2.6.7}"*) echo "client HBase ${HBASE_VERSION:-2.6.7} OK" ;; \
      *) echo "ERREUR : bin/hbase version ne répond pas" >&2; exit 1 ;; \
    esac; \
    /opt/jdk17/bin/javac -version

# Paquets Python :
#  * happybase : client HBase Thrift pour %python / %spark.pyspark. Il importe
#    pkg_resources, fourni par le paquet Ubuntu python3-setuptools : ne PAS
#    mettre setuptools à jour via pip (les versions récentes n'ont plus
#    pkg_resources) ;
#  * pile Jupyter pour %python.ipython, %spark.ipyspark et %jupyter. Versions
#    figées : le code gRPC de Zeppelin 0.12.1 (kernel_pb2.py) est généré pour
#    protobuf 3.x (protobuf >= 4 : « Descriptors cannot be created directly »),
#    et son serveur de noyau appelle execute_interactive depuis un thread, ce
#    qui exige jupyter_client < 7 (Zeppelin teste avec jupyter_client 5).
#    Combinaison vérifiée en Python 3.10 contre le serveur de noyau de Zeppelin
#    0.12.1 (noyaux "python" et "python3").
#    %python et %spark.pyspark restent en mode classique (useIPython=false) ;
#  * pandas + pandasql pour %python.sql (et z.show(df) dans %python). Avec
#    pandas 2.2, pandasql exige SQLAlchemy 2.x (1.4 : « 'Connection' object has
#    no attribute 'cursor' ») : combinaison vérifiée en Python 3.10.
RUN pip3 install --no-cache-dir \
        happybase==1.2.0 \
        jupyter-client==6.1.12 ipykernel==5.5.6 ipython==7.34.0 ipython_genutils==0.2.0 \
        grpcio==1.62.2 protobuf==3.20.3 \
        tornado==6.5.10 pyzmq==27.2.0 traitlets==5.16.1 jupyter-core==5.9.1 \
        pandas==2.2.3 numpy==1.26.4 sqlalchemy==2.0.36 pandasql==0.7.3 \
 && python3 -W ignore -c "import happybase, jupyter_client, ipykernel, grpc, google.protobuf as pb; \
print('happybase', happybase.__version__, '| jupyter_client', jupyter_client.__version__, \
'| ipykernel', ipykernel.__version__, '| grpcio', grpc.__version__, '| protobuf', pb.__version__)" \
 && python3 -W ignore -c "import pandas as pd; from pandasql import sqldf; \
df = pd.DataFrame({'v': ['a', 'b', 'a']}); \
r = sqldf('SELECT v, COUNT(*) AS n FROM df GROUP BY v', {'df': df}); \
assert r['n'].tolist() == [2, 1], r; print('pandasql OK, pandas', pd.__version__)"
COPY zeppelin/build/check_kernel_stubs.py /tmp/check_kernel_stubs.py
RUN python3 /tmp/check_kernel_stubs.py /opt/zeppelin/interpreter \
 && rm -f /tmp/check_kernel_stubs.py

# Configuration Zeppelin + notebooks de l'atelier (TP N1, démo écosystème)
COPY zeppelin/conf/zeppelin-env.sh zeppelin/conf/interpreter.json /opt/zeppelin/conf/
COPY zeppelin/notebook/ /opt/zeppelin/notebook/

ENV ZEPPELIN_HOME=/opt/zeppelin \
    ZEPPELIN_ADDR=0.0.0.0 \
    ZEPPELIN_PORT=8082 \
    HBASE_HOME=/opt/hbase \
    PATH=/opt/zeppelin/bin:/opt/hbase/bin:${PATH}

WORKDIR /opt/zeppelin
EXPOSE 8082 4040
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/opt/zeppelin/bin/zeppelin.sh"]
