# =============================================================================
# Hue 4.11.0 pour l'atelier : image officielle + deux ajustements.
#
# 1. Cookie CSRF renommé « hue_atelier_csrftoken » (au lieu de « csrftoken »).
#    Un cookie est lié au nom d'hôte (localhost), PAS au port. Toute autre
#    application Django ouverte dans le même navigateur sur localhost (un autre
#    Hue, par exemple celui du projet Big-Data-Cluster, également sur le port
#    8888) écrit le même cookie « csrftoken ». Or Hue 4.11 recopie la valeur
#    BRUTE de ce cookie dans la page (window.CSRF_TOKEN, global_js_constants.mako).
#    Dès que le cookie est réécrit ailleurs, la page et le cookie ne
#    correspondent plus : « 403 CSRF error. Sorry, your session is invalid or
#    has expired ». Le nom n'est pas paramétrable dans hue.ini : on remplace le
#    littéral dans settings.py et dans les gabarits qui le recopient. Le build
#    échoue si le remplacement n'a pas eu lieu ou s'il reste une occurrence.
#    (Le cookie de session, lui, est renommé dans z-hue.ini : [[session]] cookie_name.)
#
# 2. Démarrage via atelier-startup.sh : compte administrateur créé d'avance.
# =============================================================================
FROM gethue/hue:4.11.0

USER root

COPY atelier-startup.sh /usr/share/hue/atelier-startup.sh

WORKDIR /usr/share/hue

# $dirs et $files sont volontairement découpés en mots (listes de chemins).
# hadolint ignore=SC2086
RUN set -eux; \
    dirs="desktop/core/src desktop/libs apps"; \
    files="$(grep -rlE --include='*.py' --include='*.mako' "[\"']csrftoken[\"']" $dirs)"; \
    test -n "$files"; \
    echo "$files"; \
    sed -i -E "s/([\"'])csrftoken([\"'])/\1hue_atelier_csrftoken\2/g" $files; \
    grep -q "^CSRF_COOKIE_NAME = 'hue_atelier_csrftoken'" desktop/core/src/desktop/settings.py; \
    grep -q "hue_atelier_csrftoken" desktop/core/src/desktop/templates/global_js_constants.mako; \
    if grep -rqE --include='*.py' --include='*.mako' "[\"']csrftoken[\"']" $dirs; then \
      echo "ERREUR : il reste une référence au cookie csrftoken" >&2; exit 1; \
    fi; \
    chown hue:hue atelier-startup.sh; \
    chmod 0755 atelier-startup.sh

USER hue

CMD ["./atelier-startup.sh"]
