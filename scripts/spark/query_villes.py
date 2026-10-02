# Étape 4 (bonus) : même requête que l'atelier, exécutée par Spark SQL
#   docker exec spark-master spark-submit /opt/scripts/spark/query_villes.py
from pyspark.sql import SparkSession

spark = (SparkSession.builder
         .appName("atelier-query-villes")
         .enableHiveSupport()
         .getOrCreate())
spark.sql("SELECT ville, COUNT(*) AS nb_clients FROM default.clients GROUP BY ville").show()
spark.stop()
