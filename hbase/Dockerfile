# =============================================================================
# Image HBase 2.6.7 (binaire "hadoop3") sur JDK 17
#  * JDK 17 : comme le reste du cluster. HBase 2.6.x est la première branche
#    où JDK 17 est officiellement supporté (matrice "Java support" du guide
#    HBase ; 2.5.x : support préliminaire seulement).
#  * Hadoop : le binaire hbase-2.6.x-hadoop3 embarque ses propres jars clients
#    Hadoop 3.4.x, compatibles avec le HDFS 3.4.2 de l'atelier (HBase 2.6.2+ :
#    Hadoop 3.4.0+ supporté).
# Un seul jeu de binaires pour hbase-master, hbase-regionserver, hbase-thrift.
# =============================================================================
FROM eclipse-temurin:17-jre-jammy

ARG HBASE_VERSION=2.6.7

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash curl ca-certificates procps netcat-openbsd; \
    rm -rf /var/lib/apt/lists/*

# dlcdn ne garde que la dernière version de chaque branche : repli automatique
# sur archive.apache.org (toutes les versions) pour que le build reste
# reproductible après la sortie d'une 2.6.8.
RUN set -eux; \
    f="hbase-${HBASE_VERSION}-hadoop3-bin.tar.gz"; \
    for url in "https://dlcdn.apache.org/hbase/${HBASE_VERSION}/${f}" \
               "https://archive.apache.org/dist/hbase/${HBASE_VERSION}/${f}"; do \
        curl -fSL --retry 3 -o "/tmp/${f}" "${url}" && break; \
    done; \
    test -s "/tmp/${f}"; \
    mkdir -p /opt/hbase; \
    tar -xzf "/tmp/${f}" -C /opt/hbase --strip-components=1; \
    rm -f "/tmp/${f}"; \
    rm -rf /opt/hbase/docs; \
    mkdir -p /opt/hbase/logs /opt/hbase/tmp /opt/hbase-scripts

COPY conf/hbase-site.xml conf/hdfs-site.xml conf/core-site.xml /opt/hbase/conf/
COPY init-hbase.sh demo_clients.hbase /opt/hbase-scripts/

ENV HBASE_HOME=/opt/hbase \
    HBASE_CONF_DIR=/opt/hbase/conf \
    HBASE_MANAGES_ZK=false \
    HBASE_LOG_DIR=/opt/hbase/logs \
    PATH=/opt/hbase/bin:${PATH}

RUN set -eux; \
    chmod +x /opt/hbase-scripts/init-hbase.sh; \
    hbase version 2>&1 | head -3

WORKDIR /opt/hbase
