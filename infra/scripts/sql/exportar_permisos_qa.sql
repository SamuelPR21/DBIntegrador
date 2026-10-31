-- =====================================================================
-- EXPORTA LOS PERMISOS DE UN ROL (por defecto rol_qa) DESDE EL CLÚSTER DE TEST
-- Genera un script idempotente que se aplica en la base local de QA.
--
-- Uso (lo llama scripts/actualizar_roles_qa.sh):
--   psql -X -q -At -v rol=rol_qa -h TEST_HOST -U ... -d ... \
--        -f scripts/sql/exportar_permisos_qa.sql -o qa/permisos_qa.sql
--
-- Exporta: permisos sobre la base, esquemas, tablas/vistas/secuencias,
-- columnas, funciones/procedimientos, privilegios por defecto y
-- políticas RLS que mencionan al rol.
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path = pg_catalog;   -- fuerza nombres calificados (esquema.objeto)

WITH
rol AS (SELECT :'rol'::regrole::oid AS oid),

db AS (   -- 1. Base de datos (@DB@ se reemplaza por la base local al aplicar)
  SELECT 1 AS ord, format('GRANT %s ON DATABASE @DB@ TO %I', a.privilege_type, :'rol') AS stmt
  FROM pg_database d
  CROSS JOIN LATERAL aclexplode(d.datacl) a
  WHERE d.datname = current_database() AND a.grantee = (SELECT oid FROM rol)
),

sch AS (  -- 2. Esquemas
  SELECT 2, format('GRANT %s ON SCHEMA %I TO %I', a.privilege_type, n.nspname, :'rol')
  FROM pg_namespace n
  CROSS JOIN LATERAL aclexplode(n.nspacl) a
  WHERE a.grantee = (SELECT oid FROM rol)
),

rel AS (  -- 3. Tablas, particiones, vistas, vistas materializadas, foráneas y secuencias
  SELECT 3, format('GRANT %s ON %s %s TO %I', a.privilege_type,
                   CASE WHEN c.relkind = 'S' THEN 'SEQUENCE' ELSE 'TABLE' END,
                   c.oid::regclass, :'rol')
  FROM pg_class c
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE c.relkind IN ('r','p','v','m','f','S') AND a.grantee = (SELECT oid FROM rol)
),

col AS (  -- 4. Columnas
  SELECT 4, format('GRANT %s (%I) ON TABLE %s TO %I', a.privilege_type,
                   att.attname, att.attrelid::regclass, :'rol')
  FROM pg_attribute att
  CROSS JOIN LATERAL aclexplode(att.attacl) a
  WHERE att.attnum > 0 AND NOT att.attisdropped AND a.grantee = (SELECT oid FROM rol)
),

fn AS (   -- 5. Funciones y procedimientos
  SELECT 5, format('GRANT EXECUTE ON %s %I.%I(%s) TO %I',
                   CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
                   n.nspname, p.proname, pg_get_function_identity_arguments(p.oid), :'rol')
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL aclexplode(p.proacl) a
  WHERE p.prokind IN ('f','p') AND a.grantee = (SELECT oid FROM rol)
),

dflt AS ( -- 6. Privilegios por defecto (objetos creados en el futuro)
  SELECT 6, format('ALTER DEFAULT PRIVILEGES FOR ROLE %I%s GRANT %s ON %s TO %I',
                   pg_get_userbyid(d.defaclrole),
                   CASE WHEN n.nspname IS NULL THEN '' ELSE format(' IN SCHEMA %I', n.nspname) END,
                   a.privilege_type,
                   CASE d.defaclobjtype WHEN 'r' THEN 'TABLES'  WHEN 'S' THEN 'SEQUENCES'
                                        WHEN 'f' THEN 'FUNCTIONS' WHEN 'T' THEN 'TYPES'
                                        WHEN 'n' THEN 'SCHEMAS' END,
                   :'rol')
  FROM pg_default_acl d
  LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) a
  WHERE a.grantee = (SELECT oid FROM rol)
),

pol AS (  -- 7. Políticas RLS que mencionan al rol (se recrean con prefijo qa__)
  SELECT 7, format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %I%s%s',
                   left('qa__' || p.policyname, 63), p.schemaname, p.tablename,
                   p.permissive, p.cmd, :'rol',
                   CASE WHEN p.qual       IS NULL THEN '' ELSE ' USING ('      || p.qual       || ')' END,
                   CASE WHEN p.with_check IS NULL THEN '' ELSE ' WITH CHECK (' || p.with_check || ')' END)
  FROM pg_policies p
  WHERE :'rol' = ANY (p.roles)
),

todo(ord, stmt) AS (
  SELECT * FROM db  UNION ALL SELECT * FROM sch UNION ALL SELECT * FROM rel
  UNION ALL SELECT * FROM col UNION ALL SELECT * FROM fn
  UNION ALL SELECT * FROM dflt UNION ALL SELECT * FROM pol
)

SELECT format($plantilla$-- =====================================================================
-- Permisos de %1$s exportados desde TEST (base: %2$s) el %3$s
-- Total de sentencias: %4$s
-- GENERADO AUTOMÁTICAMENTE por scripts/actualizar_roles_qa.sh. NO EDITAR A MANO.
-- =====================================================================
DO $bloque$
DECLARE
  s       text;
  ok      int := 0;
  omitido int := 0;
BEGIN
  FOREACH s IN ARRAY ARRAY[
    %5$s
  ]::text[]
  LOOP
    BEGIN
      EXECUTE replace(s, '@DB@', quote_ident(current_database()));
      ok := ok + 1;
    EXCEPTION WHEN OTHERS THEN
      -- El objeto existe en TEST pero no en DEV (o ya existía): se avisa y se sigue
      omitido := omitido + 1;
      RAISE WARNING 'Permiso QA omitido: %% -> %%', s, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'Permisos QA aplicados: %%, omitidos: %%', ok, omitido;
END
$bloque$;
$plantilla$,
  :'rol', current_database(), to_char(now(), 'YYYY-MM-DD HH24:MI'),
  count(*),
  coalesce(string_agg(quote_literal(stmt), E',\n    ' ORDER BY ord, stmt), ''))
FROM todo;
