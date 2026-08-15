FROM postgres:18

# gettext-base solo si roles.sql sigue siendo plantilla con envsubst.
# Si roles.sql ya tiene user/pass en texto plano, podés borrar esta línea.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-18-cron \
        gettext-base && \
    rm -rf /var/lib/apt/lists/*