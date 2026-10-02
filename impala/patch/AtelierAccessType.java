/*
 * Atelier hadoop-hive-lab : correctif IMPALA-10792 pour les images officielles
 * apache/impala:4.5.2 face au metastore Apache Hive 4.1.0.
 *
 * Problème : les images officielles d'Impala sont compilées avec le client
 * metastore de Cloudera (CDP Hive 3.1.3000). Ce client se fie au champ
 * Table.accessType que calcule le metastore (MetastoreDefaultTransformer)
 * d'après les capacités déclarées par Impala. Face à un metastore Apache
 * Hive 4, ce champ n'arrive pas renseigné (0). Toute requête échoue alors :
 *   AnalysisException: Operations not supported. Table x access type is: NONE
 *
 * Correctif : quand le metastore n'a PAS renseigné le type d'accès, on le
 * calcule ici, comme le ferait MetastoreDefaultTransformer (Hive 4.1.0) pour
 * les capacités qu'Impala déclare. C'est aussi ce que fait déjà la variante
 * d'Impala compilée contre Apache Hive (fe/src/compat-apache-hive-3,
 * MetastoreShim.getAccessType). Un type d'accès fourni par le metastore est
 * toujours respecté.
 *
 * Utilisé par MetastoreShim.hasTableCapability et getTableAccessType, dont
 * le corps est remplacé au build par PatchMetastoreShim (voir build-patch.sh).
 * Compilé en bytecode Java 8, comme le reste d'Impala 4.5.2.
 */
package org.apache.impala.compat;

import static org.apache.hadoop.hive.metastore.api.hive_metastoreConstants.ACCESSTYPE_NONE;
import static org.apache.hadoop.hive.metastore.api.hive_metastoreConstants.ACCESSTYPE_READONLY;
import static org.apache.hadoop.hive.metastore.api.hive_metastoreConstants.ACCESSTYPE_READWRITE;
import static org.apache.hadoop.hive.metastore.api.hive_metastoreConstants.ACCESSTYPE_WRITEONLY;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import org.apache.hadoop.hive.metastore.api.Table;

public final class AtelierAccessType {

  /** Capacités déclarées par Impala 4.5.2 (MetastoreShim.setHiveClientCapabilities). */
  static final List<String> IMPALA_CAPABILITIES = Arrays.asList(
      "EXTWRITE", "EXTREAD", "HIVEMANAGEDINSERTREAD", "HIVEMANAGEDINSERTWRITE",
      "HIVEFULLACIDREAD", "HIVEFULLACIDWRITE", "HIVESQL", "HIVEMQT", "HIVEBUCKET2");

  /** Capacités de lecture parmi celles d'Impala. */
  private static final List<String> READ_CAPABILITIES = Arrays.asList(
      "EXTREAD", "HIVEMANAGEDINSERTREAD", "HIVEFULLACIDREAD", "HIVESQL", "HIVEMQT");

  /** Paramètre de table portant des capacités exigées (CatalogOpExecutor.CAPABILITIES_KEY). */
  private static final String OBJCAPABILITIES = "OBJCAPABILITIES";

  private AtelierAccessType() {}

  /** Type d'accès effectif : celui du metastore s'il est renseigné, sinon calculé. */
  public static byte effective(Table msTbl) {
    if (msTbl.isSetAccessType() && msTbl.getAccessType() != 0) {
      return msTbl.getAccessType();
    }
    return compute(msTbl);
  }

  /** Équivalent de MetastoreDefaultTransformer.transform() pour les capacités d'Impala. */
  static byte compute(Table msTbl) {
    String tableType = msTbl.getTableType();
    Map<String, String> params = msTbl.getParameters();
    String objCapabilities = params == null ? null : params.get(OBJCAPABILITIES);

    if (objCapabilities != null && !objCapabilities.trim().isEmpty()) {
      List<String> required =
          Arrays.asList(objCapabilities.replaceAll("\\s", "").toUpperCase().split(","));
      if (IMPALA_CAPABILITIES.containsAll(required)) return ACCESSTYPE_READWRITE;
      boolean bucketed = msTbl.isSetSd() && msTbl.getSd().getNumBuckets() > 0;
      if ("EXTERNAL_TABLE".equals(tableType) && required.contains("EXTWRITE") && !bucketed) {
        return ACCESSTYPE_READWRITE;
      }
      for (String capability : required) {
        if (READ_CAPABILITIES.contains(capability)) return ACCESSTYPE_READONLY;
      }
      return ACCESSTYPE_NONE;
    }

    if (tableType == null) return ACCESSTYPE_NONE;
    switch (tableType) {
      case "EXTERNAL_TABLE":     // EXTREAD + EXTWRITE (+ HIVEBUCKET2 si bucketée)
      case "MANAGED_TABLE":      // non ACID, insert-only ou ACID complet : capacités WRITE
        return ACCESSTYPE_READWRITE;
      case "VIRTUAL_VIEW":       // HIVESQL
      case "MATERIALIZED_VIEW":  // HIVEFULLACIDREAD + HIVEMQT
        return ACCESSTYPE_READONLY;
      default:
        return ACCESSTYPE_NONE;
    }
  }

  /** Remplace MetastoreShim.hasTableCapability (même contrat). */
  public static boolean hasTableCapability(Table msTbl, byte requiredCapability) {
    if (msTbl == null) throw new NullPointerException("msTbl");
    return requiredCapability != ACCESSTYPE_NONE
        && ((effective(msTbl) & requiredCapability) != 0);
  }

  /** Remplace MetastoreShim.getTableAccessType (même contrat). */
  public static String getTableAccessType(Table msTbl) {
    if (msTbl == null) throw new NullPointerException("msTbl");
    switch (effective(msTbl)) {
      case ACCESSTYPE_READONLY:
        return "READONLY";
      case ACCESSTYPE_WRITEONLY:
        return "WRITEONLY";
      case ACCESSTYPE_READWRITE:
        return "READWRITE";
      case ACCESSTYPE_NONE:
      default:
        return "NONE";
    }
  }
}
