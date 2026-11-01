# Restaurar la base de datos en local (QA)

Levanta en tu PC el último backup de **DEV** con los permisos de **QA**.

## Estructura del repo

```
repo/
├── backups/            ← backups de DEV (se restaura el más reciente)
└── infra/
    ├── docker-compose.yml
    ├── .env.example    ← plantilla de contraseñas
    ├── initdb/         ← scripts que crean roles, restauran y dan permisos
    ├── qa/             ← roles y permisos de QA
    └── scripts/        ← solo para el DBA
```

## Requisitos

- **Docker Desktop** instalado y **abierto** (debe decir *Engine running*).
- **Git**.
- Las contraseñas del `.env` (pídeselas al DBA).

## Restaurar

```bash
git clone <url-del-repo>
cd <repo>/infra
cp .env.example .env      # llena las contraseñas
docker compose up -d
```

Espera a que termine (puede tardar unos minutos):

```bash
docker compose ps         # listo cuando STATUS diga "healthy"
```

## Conectarte

| Host | Puerto | Base | Usuario |
|---|---|---|---|
| `localhost` | **`5433`** | `pecuario` | `member_qa` |

Antes de consultar, indica la granja (RLS):

```sql
SET app.current_granja_id = 1;
```

> En pgAdmin registra un servidor nuevo con el puerto **5433** (el 5432 es otro Postgres).

## Actualizar al último backup

```bash
git pull
docker compose down -v    # borra tu base local
docker compose up -d
```

Para apagar y prender sin perder datos: `docker compose stop` / `docker compose start`.

## Si falla

```bash
docker compose logs db
```

Corrige el problema y vuelve a empezar desde cero:

```bash
docker compose down -v && docker compose up -d
```