# =============================================================================
# impalad 4.5.2 pour l'atelier : image officielle apache/impala + correctif
# IMPALA-10792 (« Operations not supported. Table x access type is: NONE »).
#
# Les images officielles d'Impala sont compilées avec le client metastore de
# Cloudera (CDP Hive). Ce client se fie au champ Table.accessType calculé par
# le metastore. Face au metastore Apache Hive 4.1.0 de l'atelier, ce champ
# arrive vide : toutes les requêtes Impala sur les tables Hive sont refusées.
#
# Le correctif ne touche que deux méthodes de MetastoreShim
# (hasTableCapability, getTableAccessType), dans le jar impala-frontend :
# si le metastore n'a pas fourni le type d'accès, il est calculé comme le fait
# Hive 4 (MetastoreDefaultTransformer) pour les capacités d'Impala. Détails et
# sources : impala/patch/. Le build échoue si le patch ou son auto-test (exécuté
# contre les vraies classes de l'image) ne passe pas.
#
# Seul impalad est concerné : c'est lui qui analyse les requêtes.
# statestored et catalogd restent les images officielles.
# =============================================================================
ARG IMPALA_VERSION=4.5.2

FROM apache/impala:${IMPALA_VERSION}-impalad_coord_exec AS impalad-officiel

# --- Construction du jar corrigé (JDK 17 + Javassist), image jetable ---------
FROM maven:3.9-eclipse-temurin-17 AS correctif
COPY --from=impalad-officiel /opt/impala/lib/ /impala-lib/
COPY patch/ /patch/
WORKDIR /patch
RUN mvn -B -q -Dmaven.repo.local=/tmp/m2 \
      org.apache.maven.plugins:maven-dependency-plugin:3.6.1:get \
      -Dartifact=org.javassist:javassist:3.30.2-GA -Dtransitive=false \
 && mkdir -p /patch/lib \
 && cp /tmp/m2/org/javassist/javassist/3.30.2-GA/javassist-3.30.2-GA.jar /patch/lib/ \
 && bash /patch/build-patch.sh /impala-lib /patch/lib/javassist-3.30.2-GA.jar /out

# --- Image finale : l'officielle, avec le seul jar impala-frontend remplacé ---
FROM impalad-officiel AS impalad
COPY --from=correctif --chown=impala /out/ /opt/impala/lib/
