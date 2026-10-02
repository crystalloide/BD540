/*
 * Atelier : remplace, dans org.apache.impala.compat.MetastoreShim (jar
 * impala-frontend), le corps des deux seules méthodes qui lisent
 * Table.accessType, pour qu'elles délèguent à AtelierAccessType.
 * Le reste de la classe est inchangé (Javassist ne recompile que ces corps).
 * Usage : java -cp <javassist>:<helper>:<jars Impala> PatchMetastoreShim <dossier_sortie>
 */
import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;

public class PatchMetastoreShim {
  public static void main(String[] args) throws Exception {
    if (args.length != 1) {
      System.err.println("usage : PatchMetastoreShim <dossier_sortie>");
      System.exit(2);
    }
    ClassPool pool = ClassPool.getDefault();
    CtClass shim = pool.get("org.apache.impala.compat.MetastoreShim");
    CtClass table = pool.get("org.apache.hadoop.hive.metastore.api.Table");

    CtMethod has = shim.getDeclaredMethod("hasTableCapability",
        new CtClass[] {table, CtClass.byteType});
    has.setBody("{ return org.apache.impala.compat.AtelierAccessType"
        + ".hasTableCapability($1, $2); }");

    CtMethod label = shim.getDeclaredMethod("getTableAccessType", new CtClass[] {table});
    label.setBody("{ return org.apache.impala.compat.AtelierAccessType"
        + ".getTableAccessType($1); }");

    shim.writeFile(args[0]);
    System.out.println("MetastoreShim patché : hasTableCapability, getTableAccessType -> AtelierAccessType");
  }
}
