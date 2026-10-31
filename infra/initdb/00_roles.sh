#!/usr/bin/env bash
# =====================================================================
# 00 · ROLES DEL CLÚSTER LOCAL
#   1) Carga los roles de DEV (roles_dev.sql, exportado SIN contraseñas)
#      -> así el dump de DEV encuentra todos sus OWNER/GRANT/POLICY.
#   2) Agrega los roles de QA, que solo existen en TEST (rol_qa, member_qa).
#   3) Solo member_qa y sgpmp_app pueden iniciar sesión; el resto queda NOLOGIN.
# Se ejecuta UNA vez, cuando el volumen está vacío.
# =====================================================================
set -eo pipefail

ROLES_FILE=/qa/roles_dev.sql
if [[ ! -f "$ROLES_FILE" ]]; then
  echo "✖ No existe $ROLES_FILE. Haz git pull (lo genera el DBA con scripts/actualizar_roles_qa.sh)." >&2
  exit 1
fi

echo "→ [00] Cargando roles de DEV..."
# - Se omite el CREATE del superusuario del contenedor, porque ya existe.
# - Se quita "GRANTED BY x": en DEV el que otorgó fue el superusuario de arranque
#   de ese clúster (dba); aquí ese papel lo tiene $POSTGRES_USER, y PG16+ exige
#   que el otorgante tenga ADMIN sobre el rol.
grep -vE "^CREATE ROLE \"?${POSTGRES_USER}\"?;" "$ROLES_FILE" \
  | sed -E 's/ GRANTED BY [^;]+;/;/' \
  | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --quiet

echo "→ [00] Agregando roles de QA..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     --quiet -v qa_pwd="$QA_PASSWORD" -v app_pwd="$APP_PASSWORD" <<'EOSQL'
BEGIN;

-- Grupo de QA (existe en TEST, no en DEV)
SELECT 'CREATE ROLE rol_qa NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_qa') \gexec

-- Usuario de QA, con los mismos atributos que tiene en TEST
SELECT 'CREATE ROLE member_qa NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'member_qa') \gexec

ALTER ROLE member_qa PASSWORD :'qa_pwd';
GRANT rol_qa TO member_qa WITH INHERIT TRUE;

-- Usuario del backend (pruebas con Postman / Newman / Cypress)
ALTER ROLE sgpmp_app PASSWORD :'app_pwd';

-- Los usuarios de DEV (dba, member_dev, user_mig...) no inician sesión en local
SELECT format('ALTER ROLE %I NOLOGIN', rolname)
FROM pg_roles
WHERE rolcanlogin
  AND rolname NOT IN ('member_qa', 'sgpmp_app', current_user) \gexec

COMMIT;
EOSQL

echo "✔ [00] Roles listos"
