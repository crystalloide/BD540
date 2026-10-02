"""Extrait interpreter-setting.json du jar zeppelin-shell et n'y garde que %sh.

Utilisé pendant le build de l'image Zeppelin (spark/Dockerfile).
Zeppelin instancie TOUS les interpréteurs d'un groupe à la première exécution ;
or %sh.terminal (TerminalInterpreter) dépend de pty4j, volontairement exclu
(hébergé hors de Maven Central, cf. zeppelin/maven/pom.xml). On ne déclare donc
que ShellInterpreter.
"""
import json
import sys
import zipfile

jar, out = sys.argv[1], sys.argv[2]
settings = json.loads(zipfile.ZipFile(jar).read("interpreter-setting.json"))
kept = [s for s in settings if s["className"] == "org.apache.zeppelin.shell.ShellInterpreter"]
if len(kept) != 1:
    sys.exit(f"ShellInterpreter introuvable dans {jar} : {settings}")
with open(out, "w") as f:
    json.dump(kept, f, indent=2)
print("interpréteur sh :", kept[0]["name"], kept[0]["className"])
