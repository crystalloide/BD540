#!/bin/bash
# =============================================================================
# Vérifie, depuis le conteneur hue, le parcours complet d'un navigateur :
#   1. page de connexion        -> cookie CSRF de l'atelier reçu
#   2. connexion hue / hue      -> redirection (302) = identifiants acceptés
#   3. POST /api/get_config/    -> configuration de l'interface (JSON)
# L'étape 3 est le premier appel de l'interface Hue 4.11 après connexion. Ses
# erreurs sont masquées dans le navigateur : s'il échoue, l'écran reste vide.
# Usage : docker exec hue /usr/share/hue/atelier-check.sh [utilisateur] [mot_de_passe]
# =============================================================================
set -u
URL="http://localhost:8888"
USER_NAME="${1:-hue}"
USER_PASSWORD="${2:-${HUE_USER_PASSWORD:-hue}}"
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT

csrf () { awk -F'\t' '$6 == "hue_atelier_csrftoken" { v = $7 } END { print v }' "$JAR"; }

code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JAR" -b "$JAR" "$URL/hue/accounts/login/")
if [ "$code" != 200 ]; then echo "KO page de connexion : HTTP $code"; exit 1; fi
tok=$(csrf)
if [ -z "$tok" ]; then echo "KO cookie hue_atelier_csrftoken absent (image de l'atelier non utilisée ?)"; exit 1; fi

code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JAR" -b "$JAR" \
  --data-urlencode "username=$USER_NAME" --data-urlencode "password=$USER_PASSWORD" \
  --data-urlencode "csrfmiddlewaretoken=$tok" --data-urlencode "next=/" \
  "$URL/hue/accounts/login/")
if [ "$code" != 302 ]; then
  echo "KO connexion '$USER_NAME' : HTTP $code (attendu 302 ; 200 = identifiants refusés, 403 = CSRF)"
  exit 1
fi

tok=$(csrf)
out=$(curl -s -w '\n%{http_code}' -b "$JAR" -H "X-CSRFToken: $tok" \
  -H 'X-Requested-With: XMLHttpRequest' -X POST "$URL/api/get_config/")
code="${out##*$'\n'}"
body="${out%$'\n'*}"
if [ "$code" != 200 ] || ! printf '%s' "$body" | grep -q '"app_config"'; then
  echo "KO POST /api/get_config/ : HTTP $code"
  printf '%s\n' "$body" | head -c 800; echo
  exit 1
fi

echo "OK : connexion '$USER_NAME' et configuration de l'interface (/api/get_config/) fonctionnent."
