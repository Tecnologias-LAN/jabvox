# Runbook — Renombrar la base de datos y la identidad de despliegue de `chatwoot` a `jabvox`

> ⚠️ **NO ejecutado automáticamente.** Esto toca la conexión a la base de datos de producción.
> Hazlo en una **ventana de mantenimiento**, con **backup completo** y verificando cada paso.
> El nombre de la BD **no aparece en ninguna pantalla** — este cambio es solo cosmético/organizativo a nivel de infraestructura.

## Contexto

`config/database.yml` lee el nombre de la BD desde la variable de entorno `POSTGRES_DATABASE`.
Si esa variable está vacía (hoy lo está, comentada en `.env`), usa el **default** `chatwoot_production`.
Por eso tu BD real en producción se llama **`chatwoot_production`**, con usuario **`chatwoot_prod`**.

Tienes **dos caminos**. El A es el más simple y de menor riesgo.

---

## Camino A (recomendado) — No renombrar la BD, solo fijar el nombre por variable de entorno

No tocas PostgreSQL en absoluto. Dejas que la BD siga llamándose como sea internamente y lo fijas explícitamente por env. Cero downtime, cero riesgo de datos.

1. En `.env` de producción, **descomenta y fija** el nombre actual real:
   ```
   POSTGRES_DATABASE=chatwoot_production
   POSTGRES_USERNAME=chatwoot_prod
   ```
   (Esto NO cambia el nombre; solo lo hace explícito para que el default `chatwoot_*` del yml deje de importar.)

2. Cambia los **defaults** de `config/database.yml` a `jabvox_*` (puramente cosmético, ya no se usan porque el env manda):
   - `chatwoot_dev` → `jabvox_dev`
   - `chatwoot_test` → `jabvox_test`
   - `chatwoot_production` → `jabvox_production`
   - usuario default `chatwoot_prod` → `jabvox_prod`

Con esto, en el código fuente ya no aparece `chatwoot` como nombre de BD; la BD real sigue funcionando intacta. **Termina aquí si no necesitas que la BD física se llame distinto.**

---

## Camino B (completo) — Renombrar físicamente la BD y el usuario en PostgreSQL

Solo si necesitas que la base física se llame `jabvox_production`.

### 0. Backup (OBLIGATORIO)
```bash
pg_dump -Fc -U postgres -h <host> chatwoot_production > /ruta/segura/chatwoot_production_$(date +%F).dump
# Verifica que el archivo existe y pesa lo esperado antes de continuar.
```

### 1. Parar la aplicación (sin tráfico = sin conexiones abiertas)
```bash
sudo systemctl stop chatwoot.target        # o tu equivalente (web + worker + ami_listener)
```

### 2. Renombrar la BD y el usuario en PostgreSQL
```sql
-- Conéctate como superusuario (postgres). NO puede haber conexiones activas a la BD.
-- Cierra conexiones residuales si las hay:
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE datname = 'chatwoot_production' AND pid <> pg_backend_pid();

ALTER DATABASE chatwoot_production RENAME TO jabvox_production;
ALTER ROLE chatwoot_prod RENAME TO jabvox_prod;
-- (la contraseña se conserva; si quieres cambiarla: ALTER ROLE jabvox_prod WITH PASSWORD '...';)
```

### 3. Actualizar la configuración de la app
En `.env` de producción:
```
POSTGRES_DATABASE=jabvox_production
POSTGRES_USERNAME=jabvox_prod
POSTGRES_PASSWORD=<la misma contraseña>
```
Y los defaults de `config/database.yml` a `jabvox_*` (ver Camino A, paso 2).

### 4. Reiniciar y verificar
```bash
sudo systemctl start chatwoot.target
# Verifica conexión:
RAILS_ENV=production bundle exec rails runner 'puts ActiveRecord::Base.connection.current_database'
# Debe imprimir: jabvox_production
```
Comprueba que la app carga, hay datos, y entran/salen conversaciones.

### 5. Rollback (si algo falla en el paso 4)
```sql
ALTER DATABASE jabvox_production RENAME TO chatwoot_production;
ALTER ROLE jabvox_prod RENAME TO chatwoot_prod;
```
Revierte el `.env` y reinicia. (Si todo falla, restaura el dump del paso 0.)

---

## Identidad de despliegue (opcional, mismo espíritu)

Estos nombres tampoco se ven en pantalla; son del sistema operativo. Solo si quieres higiene total:

- **Redis ActionCable** (`config/cable.yml`): `channel_prefix` usa `chatwoot_<env>_action_cable`.
  Cambiarlo en caliente deja mensajes en cola huérfanos un instante. Hazlo en la misma ventana de parada.
- **systemd / nginx / usuario de sistema** (`deployment/`): archivos `chatwoot-*.service`, `chatwoot.target`,
  `nginx_chatwoot.conf`, usuario `chatwoot`, rutas `/home/chatwoot`. Renombrar implica:
  `systemctl disable` de los viejos, crear los nuevos, mover el home, reconfigurar nginx. Es una migración de servidor, no un find-replace.
- **`.github/workflows/production-deployment.yml`**: si referencia los servicios/usuario, actualízalo a la par.

> Recomendación: haz el **Camino A** (cosmético, sin riesgo) y deja systemd/nginx/usuario como están salvo que estés reinstalando el servidor desde cero. Nadie ve esos nombres y renombrarlos solo añade superficie de fallo.
