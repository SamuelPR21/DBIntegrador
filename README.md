# SGP - Entorno de Base de Datos (PostgreSQL + Docker)

Guía para levantar la base de datos del proyecto en local usando Docker.

## Requisitos previos

- Tener [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado y corriendo.
- Tener estos archivos en la misma carpeta:
  - `dockerfile`
  - `docker-compose.yml`
  - `roles.sql`
  - `backup7_1_0.dump`

> **Nota:** no subas `backup7_1_0.dump` ni las contraseñas reales al repositorio si el repo es público o tiene gente externa al equipo con acceso.

## Paso 1: Levantar el contenedor

Desde la carpeta donde están los archivos, corre:

```bash
docker compose up -d
```

Esto va a:
- Construir la imagen de Postgres (basada en `postgres:18` + extensión `pg_cron`).
- Crear el contenedor `SGP`.
- Crear el volumen `pgdata` (donde vive la data, persiste aunque apagues el contenedor).
- Exponer el puerto `5433` en tu máquina (mapeado al `5432` interno).

Verifica que el contenedor esté corriendo:

```bash
docker ps
```

Deberías ver `SGP` en la lista con estado `Up`.

## Paso 2: Restaurar los roles

Este paso crea los roles/usuarios que necesita la base de datos (incluyendo el superusuario `dba` con su contraseña real, y los demás roles de la app).

```bash
docker exec -i SGP psql -U dba -d dba -f /scripts/roles.sql
```

Si todo sale bien, no deberías ver errores en la salida (algunos `NOTICE` son normales, los `ERROR` no).

## Paso 3: Restaurar el backup

Este paso restaura el dump completo de la base de datos (tablas, datos, funciones, etc.) sobre los roles ya creados.

```bash
docker exec -i SGPMP pg_restore -U dba -d dba --no-owner --role=dba /backup/backup7_1_0.dump
```

- `--no-owner`: evita que intente asignar propietarios originales del dump que podrían no coincidir con tus roles locales.
- `--role=dba`: fuerza que los objetos restaurados queden bajo el rol `dba`.

> Es normal ver algunos warnings de objetos que ya existen o de extensiones — mientras no se corte el proceso con un `ERROR` fatal, está bien.

## Paso 4: Conectarte a la base de datos

Usa cualquier cliente (DBeaver, pgAdmin, TablePlus, extensión de Postgres en VSCode, etc.) con estos datos de conexión:

| Parámetro | Valor |
|---|---|
| Host | `localhost` |
| Puerto | `5433` |
| Base de datos | `dba` |
| Usuario | `dba` |
| Contraseña | *(te la paso yo personalmente, no va en este README)* |

## Comandos útiles

Apagar el contenedor (sin perder los datos, quedan en el volumen `pgdata`):
```bash
docker compose down
```

Apagar y **borrar todo** (incluyendo la data, para empezar de cero):
```bash
docker compose down -v
```

Ver logs del contenedor en vivo:
```bash
docker logs -f SGPMP
```

Entrar a una consola `psql` dentro del contenedor:
```bash
docker exec -it SGPMP psql -U dba -d dba
```

## Si algo sale mal

- Si `docker compose up -d` falla, revisa que el puerto `5433` no esté ocupado por otro proceso en tu máquina.
- Si necesitas repetir el proceso desde cero (por ejemplo, si el restore falló a la mitad), corre `docker compose down -v` y vuelve a empezar desde el Paso 1.
- Cualquier error raro, mándame el log completo (`docker logs SGPMP`) antes de intentar arreglarlo por tu cuenta.
