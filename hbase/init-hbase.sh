#!/bin/bash
# =============================================================================
# init-hbase.sh — service one-shot "hbase-init"
# Attend qu'HBase soit opérationnel (master actif + RegionServer enregistré,
# hbase:meta en ligne), puis crée la table de démonstration "clients_hbase"
# si elle n'existe pas encore. Idempotent.
# =============================================================================
set -uo pipefail

MAX_RETRIES=60   # 60 x 10 s = 10 minutes max
echo "================================================================"
echo " hbase-init : attente de la disponibilité d'HBase..."
echo "================================================================"

for i in $(seq 1 "${MAX_RETRIES}"); do
  # "status" n'affiche "1 active master ... 1 servers" que lorsque le master
  # est initialisé et qu'au moins un RegionServer est en ligne.
  if echo "status" | hbase shell -n 2>/dev/null | grep -Eq "1 active master.*[1-9][0-9]* servers"; then
    echo "  OK - HBase opérationnel"
    break
  fi
  if [ "${i}" -eq "${MAX_RETRIES}" ]; then
    echo "ERREUR : HBase n'est pas opérationnel après $((MAX_RETRIES * 10)) s"
    exit 1
  fi
  echo "  -> HBase pas encore prêt, tentative ${i}/${MAX_RETRIES} (attente 10s)..."
  sleep 10
done

if echo "exists 'clients_hbase'" | hbase shell -n 2>/dev/null | grep -q "does exist"; then
  echo "  OK - table clients_hbase déjà présente, rien à faire."
  exit 0
fi

echo "Création de la table de démonstration clients_hbase..."
hbase shell -n /opt/hbase-scripts/demo_clients.hbase
rc=$?
if [ "${rc}" -ne 0 ]; then
  echo "ERREUR : création de clients_hbase en échec (code ${rc})"
  exit "${rc}"
fi
echo "================================================================"
echo " hbase-init : TERMINÉ avec succès (table clients_hbase créée)"
echo "================================================================"
