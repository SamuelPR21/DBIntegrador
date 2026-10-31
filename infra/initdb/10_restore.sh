#!/usr/bin/env bash
# =====================================================================
# 10 · RESTAURA EL ÚLTIMO BACKUP DE DEV
#   - Busca en /backups los archivos que cumplen $BACKUP_PATTERN
#     (por defecto backup_sgpmp_dev_*.dump) y toma el más reciente por
#     NOMBRE (la fecha AAAA-MM-DD del nombre ordena bien).
#     No se usa la fecha de modificación: después de un git clone/pull
#     todos los archivos tienen la misma fecha.
#   - Detecta el formato: custom (pg_dump -Fc) -> pg_restore,
#     SQL plano -> psql.
#   - Verifica checksum (si existe .sha256) y que no sea un puntero de Git LFS.
#   - Restaura todo o nada.
# =====================================================================
set -eo pipefail
shopt -s nullglob

PATTERN="${BACKUP_PATTERN:-backup_sgpmp_dev_*.dump}"
# shellcheck disable=SC2206  # se quiere expansión del glob
dumps=(/backups/$PATTERN)
if (( ${#dumps[@]} == 0 )); then
  echo "✖ [10] No hay archivos $PATTERN en la carpeta backups/. Haz git pull." >&2
  exit 1
fi
latest=$(printf '%s\n' "${dumps[@]}" | sort | tail -n 1)
echo "→ [10] Backup a restaurar: $(basename "$latest") (de ${#dumps[@]} disponibles)"

# Un puntero de Git LFS es un archivo de texto de ~130 bytes, no el backup real
if head -c 200 "$latest" | grep -q "git-lfs.github.com/spec"; then
  echo "✖ [10] $(basename "$latest") es un puntero de Git LFS, no el backup." >&2
  echo "       Corre:  git lfs install  &&  git lfs pull" >&2
  exit 1
fi

if [[ -f "$latest.sha256" ]]; then
  (cd /backups && sha256sum --quiet -c "$(basename "$latest").sha256") \
    || { echo "✖ [10] El checksum no coincide: backup corrupto o incompleto." >&2; exit 1; }
  echo "✔ [10] Checksum OK"
fi

echo "→ [10] Restaurando (puede tardar unos minutos)..."
if [[ "$(head -c 5 "$latest")" == "PGDMP" ]]; then
  # Formato custom (pg_dump -Fc)
  pg_restore --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
             --exit-on-error --single-transaction "$latest"
else
  # SQL plano (pg_dump sin -Fc)
  psql -v ON_ERROR_STOP=1 --single-transaction --quiet \
       --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$latest"
fi

echo "✔ [10] Backup restaurado"
