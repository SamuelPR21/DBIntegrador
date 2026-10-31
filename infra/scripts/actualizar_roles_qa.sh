#!/usr/bin/env bash
# =====================================================================
# SOLO PARA EL DBA · Actualiza los archivos de roles y permisos de QA
#   Tus backups siguen con tu proceso de siempre; este script NO los toca.
#
#   1. Roles de DEV, SIN contraseñas            -> infra/qa/roles_dev.sql
#   2. Permisos de rol_qa exportados desde TEST -> infra/qa/permisos_qa.sql
#
# Córrelo cuando cambies roles en DEV o permisos de QA en TEST
# (no hace falta con cada backup).
#
# Uso:  bash scripts/actualizar_roles_qa.sh
# Requiere: Docker y el archivo .env.dba (copia de .env.dba.example)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."            # carpeta infra/
export MSYS_NO_PATHCONV=1          # Git Bash en Windows: no traducir rutas de Docker

[[ -f .env.dba ]] || { echo "✖ Falta .env.dba (copia .env.dba.example)" >&2; exit 1; }
set -a; source .env.dba; set +a

if ! docker info >/dev/null 2>&1; then
  echo "✖ Docker no está corriendo. Abre Docker Desktop, espera a que diga" >&2
  echo "  'Engine running' y vuelve a ejecutar este script." >&2
  exit 1
fi

PG_IMAGE="${PG_IMAGE:-postgres:18.0}"   # clientes de la misma versión que los clústeres
QA_ROLE="${QA_ROLE:-rol_qa}"
mkdir -p qa

# En Linux/macOS se corre con tu usuario para que los archivos no queden de root
USER_FLAG=()
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]] || USER_FLAG=(--user "$(id -u):$(id -g)")

# Ejecuta clientes de Postgres 18 desde Docker (no depende de lo instalado en el PC)
pg() {
  docker run --rm -i "${USER_FLAG[@]}" -e PGPASSWORD \
    -v "$PWD:/work" -w /work "$PG_IMAGE" "$@"
}

echo "→ 1/2 Roles de DEV, sin contraseñas ($DEV_HOST)..."
PGPASSWORD="$DEV_PASSWORD" pg pg_dumpall -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" \
  -l "$DEV_DB" --roles-only --no-role-passwords -f qa/roles_dev.sql.tmp
mv qa/roles_dev.sql.tmp qa/roles_dev.sql

echo "→ 2/2 Permisos de $QA_ROLE desde TEST ($TEST_HOST)..."
PGPASSWORD="$TEST_PASSWORD" pg psql -X -q -At -v ON_ERROR_STOP=1 -v rol="$QA_ROLE" \
  -h "$TEST_HOST" -p "$TEST_PORT" -U "$TEST_USER" -d "$TEST_DB" \
  -f scripts/sql/exportar_permisos_qa.sql -o qa/permisos_qa.sql.tmp
mv qa/permisos_qa.sql.tmp qa/permisos_qa.sql
grep -m1 "Total de sentencias" qa/permisos_qa.sql || true

echo "✔ Listo. Revisa los cambios y súbelos:"
echo "    git add infra/qa && git commit -m \"chore(qa): actualiza roles y permisos QA\" && git push"