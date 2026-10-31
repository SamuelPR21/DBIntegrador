#!/usr/bin/env bash
# =====================================================================
# 20 · PERMISOS DE QA (iguales a los del clúster de TEST)
#   El dump de DEV no trae permisos para rol_qa porque ese rol no existe
#   en DEV. El DBA exporta los permisos de rol_qa desde TEST al archivo
#   permisos_qa.sql y aquí se aplican sobre la base restaurada.
#   Si un objeto de TEST no existe en DEV, ese permiso se omite con aviso.
# =====================================================================
set -eo pipefail

PERMS_FILE=/qa/permisos_qa.sql
if [[ ! -f "$PERMS_FILE" ]]; then
  echo "✖ [20] No existe $PERMS_FILE: member_qa quedaría sin permisos. Haz git pull." >&2
  exit 1
fi

echo "→ [20] Aplicando permisos de QA..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     --quiet -f "$PERMS_FILE"

# Resumen: cuántas tablas puede leer member_qa
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -At <<'EOSQL'
SELECT '✔ [20] member_qa puede leer ' || count(*) || ' tablas/vistas'
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','p','v','m')
  AND n.nspname NOT IN ('pg_catalog','information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND has_schema_privilege('member_qa', n.oid, 'USAGE')
  AND has_table_privilege('member_qa', c.oid, 'SELECT');
EOSQL
