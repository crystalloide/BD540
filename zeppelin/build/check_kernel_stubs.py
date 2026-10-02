"""Contrôle de build : la pile Python installée fait-elle tourner le code
Jupyter/IPython de Zeppelin (%python.ipython, %spark.ipyspark, %jupyter) ?

1. Extrait kernel_pb2.py / kernel_pb2_grpc.py des jars Zeppelin de l'image et
   les importe avec le protobuf / grpcio installés. protobuf >= 4 échoue ici :
   « Descriptors cannot be created directly ».
2. Vérifie que jupyter_client trouve les noyaux demandés par Zeppelin :
   "python" (IPythonInterpreter) et "python3" (%jupyter par défaut).

Usage : python3 check_kernel_stubs.py /opt/zeppelin/interpreter
Échec = build en échec.
"""
import glob
import importlib
import os
import sys
import tempfile
import zipfile

root = sys.argv[1]
stubs = ("grpc/jupyter/kernel_pb2.py", "grpc/jupyter/kernel_pb2_grpc.py")
found = None
# jupyter/ et python/ d'abord, puis tout l'arbre des interpréteurs
candidates = (sorted(glob.glob(os.path.join(root, "jupyter", "**", "*.jar"), recursive=True))
              + sorted(glob.glob(os.path.join(root, "python", "**", "*.jar"), recursive=True))
              + sorted(glob.glob(os.path.join(root, "**", "*.jar"), recursive=True)))
for jar in candidates:
    with zipfile.ZipFile(jar) as z:
        names = set(z.namelist())
        if all(s in names for s in stubs):
            found = jar
            tmp = tempfile.mkdtemp()
            for s in stubs:
                with open(os.path.join(tmp, os.path.basename(s)), "wb") as f:
                    f.write(z.read(s))
            break
if not found:
    sys.exit("ERREUR : stubs gRPC Jupyter introuvables dans les jars de " + root)

sys.path.insert(0, tmp)
importlib.import_module("kernel_pb2")
importlib.import_module("kernel_pb2_grpc")
print("stubs gRPC de Zeppelin importés (" + os.path.relpath(found, root) + ")")

# Même chemin que le serveur de noyau de Zeppelin (start_new_kernel crée un
# KernelManager) : "python" y est un alias de "python3".
from jupyter_client.manager import KernelManager  # noqa: E402

for name in ("python", "python3"):
    km = KernelManager(kernel_name=name)
    print("noyau Jupyter '%s' -> %s : %s"
          % (name, km.kernel_name, " ".join(km.kernel_spec.argv[:3])))
print("OK : pile Jupyter compatible avec Zeppelin")
