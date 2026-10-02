/*
 * Atelier : auto-test exécuté pendant le build de l'image impalad, contre la
 * VRAIE classe Table (client metastore CDP) embarquée par l'image officielle.
 * Puis vérification que MetastoreShim patché délègue bien à AtelierAccessType
 * (appel des méthodes par réflexion, sans initialiser le reste d'Impala).
 * Échec = build en échec.
 */
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Map;

import org.apache.hadoop.hive.metastore.api.Table;
import org.apache.impala.compat.AtelierAccessType;

public class AtelierAccessTypeSelfTest {
  private static int failures = 0;

  private static Table table(String type, String objCapabilities) {
    Table t = new Table();
    t.setTableName("t");
    t.setDbName("d");
    t.setTableType(type);
    Map<String, String> params = new HashMap<>();
    if (objCapabilities != null) params.put("OBJCAPABILITIES", objCapabilities);
    t.setParameters(params);
    return t;
  }

  private static void check(String label, Object actual, Object expected) {
    boolean ok = expected.equals(actual);
    System.out.println((ok ? "  [OK] " : "  [KO] ") + label + " : " + actual
        + (ok ? "" : " (attendu " + expected + ")"));
    if (!ok) failures++;
  }

  public static void main(String[] args) throws Exception {
    final byte read = 2 | 4 | 8;   // Analyzer.ensureTableSupported
    final byte write = 4 | 8;      // Analyzer.ensureTableWriteSupported

    System.out.println("Auto-test AtelierAccessType (classe Table : "
        + Table.class.getProtectionDomain().getCodeSource().getLocation() + ")");

    Table ext = table("EXTERNAL_TABLE", null);
    check("table externe, accessType absent -> lecture", AtelierAccessType.hasTableCapability(ext, read), true);
    check("table externe, accessType absent -> écriture", AtelierAccessType.hasTableCapability(ext, write), true);
    check("table externe -> libellé", AtelierAccessType.getTableAccessType(ext), "READWRITE");

    Table managed = table("MANAGED_TABLE", null);
    managed.getParameters().put("transactional", "true");
    check("table gérée ACID -> lecture", AtelierAccessType.hasTableCapability(managed, read), true);

    Table view = table("VIRTUAL_VIEW", null);
    check("vue -> lecture", AtelierAccessType.hasTableCapability(view, read), true);
    check("vue -> écriture refusée", AtelierAccessType.hasTableCapability(view, write), false);

    Table forcedNone = table("EXTERNAL_TABLE", null);
    forcedNone.setAccessType((byte) 1);
    check("accessType NONE fourni par le metastore -> respecté", AtelierAccessType.hasTableCapability(forcedNone, read), false);

    Table forcedRo = table("EXTERNAL_TABLE", null);
    forcedRo.setAccessType((byte) 2);
    check("accessType READONLY fourni -> écriture refusée", AtelierAccessType.hasTableCapability(forcedRo, write), false);

    check("OBJCAPABILITIES EXTREAD,EXTWRITE -> READWRITE",
        AtelierAccessType.getTableAccessType(table("EXTERNAL_TABLE", "EXTREAD, extwrite")), "READWRITE");
    check("OBJCAPABILITIES inconnue -> NONE",
        AtelierAccessType.getTableAccessType(table("MANAGED_TABLE", "SPARKWRITE")), "NONE");
    check("capacité NONE demandée -> toujours refusée",
        AtelierAccessType.hasTableCapability(ext, (byte) 1), false);

    // MetastoreShim patché : appel direct des deux méthodes statiques
    if (args.length > 0 && "--shim".equals(args[0])) {
      Class<?> shim = Class.forName("org.apache.impala.compat.MetastoreShim", false,
          AtelierAccessTypeSelfTest.class.getClassLoader());
      Method has = shim.getMethod("hasTableCapability", Table.class, byte.class);
      Method label = shim.getMethod("getTableAccessType", Table.class);
      try {
        check("MetastoreShim.hasTableCapability patché", has.invoke(null, ext, read), true);
        check("MetastoreShim.getTableAccessType patché", label.invoke(null, ext), "READWRITE");
      } catch (java.lang.reflect.InvocationTargetException e) {
        // L'initialisation statique de MetastoreShim peut exiger tout Impala :
        // dans ce cas, la vérification par javap (build-patch.sh) fait foi.
        System.out.println("  [--] appel direct de MetastoreShim impossible hors d'Impala ("
            + e.getCause() + ") : vérification par javap");
      } catch (ExceptionInInitializerError | NoClassDefFoundError e) {
        System.out.println("  [--] appel direct de MetastoreShim impossible hors d'Impala ("
            + e + ") : vérification par javap");
      }
    }

    if (failures > 0) {
      System.out.println("ÉCHEC : " + failures + " vérification(s) en erreur");
      System.exit(1);
    }
    System.out.println("Auto-test réussi");
  }
}
