# Test rapide Spark <-> metastore Hive <-> HDFS (utilisé par scripts/check_stack.sh)
#   docker exec spark-master spark-submit /opt/scripts/spark/smoke_test.py
from pyspark.sql import SparkSession

spark = (SparkSession.builder
         .appName("smoke-test-atelier")
         .enableHiveSupport()
         .getOrCreate())

dbs = [r[0] for r in spark.sql("SHOW DATABASES").collect()]
print("Bases visibles depuis Spark :", dbs)
n = spark.table("sales_db.transactions").count()
print(f"SPARK_OK spark={spark.version} transactions={n}")
spark.stop()
