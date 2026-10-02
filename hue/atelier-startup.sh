#!/bin/bash
# =============================================================================
# Démarrage de Hue pour l'atelier. Remplace startup.sh de l'image officielle,
# qui fait seulement « hue migrate » puis « supervisor ». Entre les deux :
#
#   1. Compte « admin » (secours). Sa seule présence fait sortir Hue du mode
#      « première connexion », où l'écran « Create your account » refuse le
#      nom « hue ».
#   2. Compte principal « hue » / « hue », administrateur : activation de
#      l'utilisateur interne de Hue (voir atelier_hue_user.py).
#
# Les deux étapes sont idempotentes. En cas d'échec, Hue démarre quand même et
# le message reste visible dans « docker logs hue ».
# =============================================================================
set -e
cd /usr/share/hue

./build/env/bin/hue migrate

ADMIN_USER="${HUE_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${HUE_ADMIN_PASSWORD:-admin}"
if DJANGO_SUPERUSER_PASSWORD="$ADMIN_PASSWORD" ./build/env/bin/hue createsuperuser \
     --noinput --username "$ADMIN_USER" --email "${ADMIN_USER}@atelier.local" >/dev/null 2>&1; then
  echo "[atelier] Compte de secours Hue créé : ${ADMIN_USER}"
else
  echo "[atelier] Compte de secours Hue '${ADMIN_USER}' déjà présent."
fi

if ! ./build/env/bin/hue shell -c "$(cat /usr/share/hue/atelier_hue_user.py)"; then
  echo "[atelier] ATTENTION : activation du compte 'hue' impossible (voir ci-dessus)." >&2
fi

exec ./build/env/bin/supervisor
