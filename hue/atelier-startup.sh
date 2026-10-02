#!/bin/bash
# =============================================================================
# Démarrage de Hue pour l'atelier. Remplace startup.sh de l'image officielle,
# qui fait seulement « hue migrate » puis « supervisor ». On ajoute entre les
# deux la création d'un compte administrateur.
#
# Sans ce compte, la première visite affiche « Create your account ». Or le
# nom « hue » y est refusé : Hue le réserve à son utilisateur interne (désactivé)
# qui possède les exemples. Le compte d'atelier est donc créé d'avance.
# L'opération est idempotente : si le compte existe déjà, rien n'est modifié
# (mot de passe compris).
# =============================================================================
set -e
cd /usr/share/hue

./build/env/bin/hue migrate

ADMIN_USER="${HUE_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${HUE_ADMIN_PASSWORD:-admin}"

if DJANGO_SUPERUSER_PASSWORD="$ADMIN_PASSWORD" ./build/env/bin/hue createsuperuser \
     --noinput --username "$ADMIN_USER" --email "${ADMIN_USER}@atelier.local"; then
  echo "[atelier] Compte administrateur Hue créé : ${ADMIN_USER}"
else
  echo "[atelier] Compte administrateur Hue '${ADMIN_USER}' déjà présent : rien à faire."
fi

exec ./build/env/bin/supervisor
