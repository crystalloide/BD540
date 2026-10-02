# =============================================================================
# Active le compte « hue » de Hue, exécuté par « hue shell -c » au démarrage.
#
# Hue crée lui-même un utilisateur interne « hue » (id 1100713), DÉSACTIVÉ et
# sans mot de passe, propriétaire des exemples. Il ne peut donc ni se connecter
# ni être recréé depuis l'écran « Create your account ». On l'active ici, avec
# les droits administrateur (accès complet) et le mot de passe HUE_USER_PASSWORD.
# Hue ne réinitialise jamais ces attributs (useradmin.models.install_sample_user
# retrouve l'utilisateur par son id sans les modifier).
#
# Idempotent : le mot de passe n'est défini que s'il n'existe pas encore.
# Un mot de passe changé ensuite dans Hue est conservé.
# =============================================================================
import os

from useradmin.models import install_sample_user

password = os.environ.get('HUE_USER_PASSWORD', 'hue')
user = install_sample_user()
if user is None:
  raise SystemExit("[atelier] Utilisateur interne « hue » introuvable : compte non activé.")

changes = []
if not user.is_active:
  user.is_active = True
  changes.append('activé')
if not user.is_superuser:
  user.is_superuser = True
  changes.append('administrateur')
if not user.has_usable_password():
  user.set_password(password)
  changes.append('mot de passe défini')
user.save()

print("[atelier] Compte Hue « %s » : %s" % (user.username, ', '.join(changes) or 'déjà prêt'))
