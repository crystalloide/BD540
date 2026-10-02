-- =============================================================================
-- Données de démonstration partagées par Hive, Spark, Impala, Zeppelin et Hue.
-- Exécuté automatiquement au démarrage par le service one-shot "lab-init"
-- (scripts/lab-init.sh). Idempotent : peut être relancé sans risque.
--
-- Table EXTERNE au format texte : lisible telle quelle par les quatre moteurs
-- (une table Hive ACID "managée" ne serait lisible ni par Spark ni par Impala).
-- customer_id reprend id_client de data/clients.csv (jointures possibles avec
-- la table "clients" créée à l'étape 2 de l'atelier).
-- =============================================================================
CREATE DATABASE IF NOT EXISTS sales_db
  COMMENT 'Base de démonstration : ventes (TP Zeppelin, Hue, Impala, Spark)';

CREATE EXTERNAL TABLE IF NOT EXISTS sales_db.transactions (
  transaction_id   INT,
  transaction_date DATE,
  customer_id      STRING,
  product          STRING,
  category         STRING,
  quantity         INT,
  unit_price       DECIMAL(10,2),
  amount           DECIMAL(12,2),
  city             STRING,
  payment_method   STRING
)
COMMENT 'Transactions de démonstration (150 lignes, data/transactions.csv)'
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/user/hadoop/demo/transactions';

-- Métadonnées uniquement (aucun job Tez au démarrage du lab) : le comptage des
-- lignes est vérifié par scripts/check_stack.sh.
SHOW TABLES IN sales_db;
