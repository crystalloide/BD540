#!/bin/bash
# =============================================================================
# Atelier : construit le jar impala-frontend corrigé (IMPALA-10792).
# Usage : build-patch.sh <dossier_lib_impala> <javassist.jar> <dossier_sortie>
#   <dossier_lib_impala> : /opt/impala/lib de l'image officielle impalad
# Produit <dossier_sortie>/impala-frontend-*.jar (même nom que l'original).
# Toute anomalie fait échouer le build (aucun jar partiellement patché).
# =============================================================================
set -euo pipefail
LIB="$1"; JAVASSIST="$2"; OUT="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

shopt -s nullglob
FRONTEND=()
for j in "${LIB}"/impala-frontend-*.jar; do
  case "$j" in *-tests.jar) ;; *) FRONTEND+=("$j") ;; esac
done
if [ "${#FRONTEND[@]}" -ne 1 ]; then
  echo "ERREUR : ${#FRONTEND[@]} jar impala-frontend trouvé(s) dans ${LIB} (1 attendu)" >&2
  exit 1
fi
FE="${FRONTEND[0]}"
NAME="$(basename "${FE}")"
CP="${LIB}/*"
# Sorties des outils Java en UTF-8 (messages accentués)
JOPTS=(-Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dstdout.encoding=UTF-8)
echo "Jar à corriger : ${NAME}"

mkdir -p "${WORK}/helper" "${WORK}/tool" "${WORK}/patched" "${OUT}"

# 1. Classe d'aide, en bytecode Java 8 comme Impala 4.5.2
javac -encoding UTF-8 -nowarn --release 8 -cp "${CP}" -d "${WORK}/helper" "${HERE}/AtelierAccessType.java"

# 2. Auto-test contre la vraie classe Table de l'image
javac -encoding UTF-8 -nowarn --release 8 -cp "${WORK}/helper:${CP}" -d "${WORK}/tool" \
  "${HERE}/AtelierAccessTypeSelfTest.java"
java "${JOPTS[@]}" -cp "${WORK}/tool:${WORK}/helper:${CP}" AtelierAccessTypeSelfTest

# 3. Patch de MetastoreShim (Javassist placé avant les jars d'Impala)
javac -encoding UTF-8 -nowarn -cp "${JAVASSIST}" -d "${WORK}/tool" "${HERE}/PatchMetastoreShim.java"
java "${JOPTS[@]}" -cp "${WORK}/tool:${JAVASSIST}:${WORK}/helper:${CP}" PatchMetastoreShim "${WORK}/patched"

# 4. Nouveau jar : copie de l'original + 2 classes
cp "${FE}" "${OUT}/${NAME}"
jar uf "${OUT}/${NAME}" \
  -C "${WORK}/patched" org/apache/impala/compat/MetastoreShim.class \
  -C "${WORK}/helper" org/apache/impala/compat/AtelierAccessType.class

# 5. Vérifications du jar produit
calls="$(javap -c -cp "${OUT}/${NAME}" org.apache.impala.compat.MetastoreShim \
  | grep -c 'org/apache/impala/compat/AtelierAccessType\.\(hasTableCapability\|getTableAccessType\)' || true)"
if [ "${calls}" -ne 2 ]; then
  echo "ERREUR : MetastoreShim ne délègue pas à AtelierAccessType (${calls} appel(s) trouvé(s), 2 attendus)" >&2
  exit 1
fi
major() { javap -v -cp "$1" "$2" | awk '/major version/ {print $3; exit}'; }
orig_major="$(major "${FE}" org.apache.impala.compat.MetastoreShim)"
new_major="$(major "${OUT}/${NAME}" org.apache.impala.compat.MetastoreShim)"
helper_major="$(major "${OUT}/${NAME}" org.apache.impala.compat.AtelierAccessType)"
if [ "${orig_major}" != "${new_major}" ] || [ "${helper_major}" -gt "${orig_major}" ]; then
  echo "ERREUR : versions de bytecode incohérentes (origine ${orig_major}, patché ${new_major}, aide ${helper_major})" >&2
  exit 1
fi
java "${JOPTS[@]}" -cp "${WORK}/tool:${OUT}/${NAME}:${CP}" AtelierAccessTypeSelfTest --shim
echo "OK : ${NAME} corrigé (bytecode ${new_major}, MetastoreShim délègue à AtelierAccessType)"
