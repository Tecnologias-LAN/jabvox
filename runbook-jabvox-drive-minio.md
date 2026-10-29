# Runbook — jabvox-drive (almacenamiento MinIO multiempresa)

Almacenamiento privado, multiempresa y resiliente para Jabvox, sobre MinIO
(compatible S3). Aislamiento duro por empresa mediante prefijo de objeto
`acct-<id>/` **forzado por policy IAM de MinIO** (no solo por la app).

> Jabvox corre desde código fuente (no en Docker). MinIO sí corre como servicio
> (contenedor en dev; binario/servicio del SO o contenedor en prod). La app habla
> con MinIO por la API S3.

---

## 1. Arquitectura (resumen)

- **2 buckets**: `jabvox-drive` (principal) y `jabvox-drive-overflow` (excedentes /
  cuarentena por cuota). Ambos **privados** (sin acceso anónimo).
- **Prefijo por cuenta**: cada cuenta usa `acct-<id>/...`. Nunca se confía en un
  `account_id` del cliente: la cuenta se resuelve desde la sesión autenticada
  (`Current.account`) y el prefijo se deriva de ahí.
- **Aislamiento duro**: cada cuenta de ejecución en MinIO tiene una policy IAM que
  solo permite operar sobre su prefijo. Un intento de leer/listar el prefijo de
  otra cuenta → `AccessDenied (403)` desde MinIO, aunque la app tuviera un bug.
- **Cuota** desde el plan: `JabvoxPlan.storage_gb` → `accounts.limits` →
  `account.storage_quota_bytes`. Reservas atómicas en PostgreSQL (sin carrera).
- **Resiliencia**: la ingesta de medios entrantes se registra en una cola durable
  (`jabvox_drive_pending_operations`) antes de tocar MinIO; si MinIO cae, el
  mensaje no se pierde y los jobs reintentan con backoff+jitter, idempotentes.
- **Servir archivos**: SIEMPRE a través de Jabvox (validación de permisos +
  presigned de vida corta o streaming con cabeceras seguras). MinIO nunca es
  accesible desde el navegador.

Componentes de código:
- `Jabvox::Drive::StorageService` — único punto de I/O con MinIO; fuerza prefijo.
- `Jabvox::Drive::QuotaService` — reservas atómicas, overflow, summary.
- `Jabvox::Drive::OverflowService` — decide principal vs excedente.
- `Jabvox::Drive::ReconciliationService` — regularización al ampliar cuota y
  reconciliación de huérfanos.
- Modelos `JabvoxDriveFile`, `JabvoxDriveFolder`, `JabvoxDriveStorageAccount`,
  `JabvoxDrivePendingOperation`.
- Jobs `Jabvox::Drive::MediaIngestJob`, `PendingOperationRetryJob`,
  `QuotaRegularizationJob`.

---

## 2. Instalación de MinIO

### 2.1 Desarrollo (Docker, macOS/Linux)

La imagen oficial `minio/minio` de Docker Hub quedó restringida (requiere auth).
Se usa una imagen pública equivalente. Solo escucha en `127.0.0.1` (sin exposición
pública) y persiste en un volumen.

```bash
docker run -d \
  --name jabvox-minio-dev \
  --restart unless-stopped \
  -p 127.0.0.1:9000:9000 \
  -p 127.0.0.1:9001:9001 \
  -e MINIO_ROOT_USER=jabvox-admin \
  -e MINIO_ROOT_PASSWORD='<secreto-fuerte>' \
  -v ~/jabvox-minio-data:/bitnami/minio/data \
  bitnamilegacy/minio:2025.7.23-debian-12-r5 \
  server /data --console-address ":9001"
```

> API S3: `http://127.0.0.1:9000` · Consola web: `http://127.0.0.1:9001`.
> Health: `curl -sf http://127.0.0.1:9000/minio/health/live`.

### 2.2 Producción

- Instalar MinIO como servicio del SO (binario oficial + unidad systemd) o como
  contenedor gestionado, detrás de la red privada. **No exponer** 9000/9001 a
  Internet; solo accesible desde los servicios Jabvox autorizados (app + workers).
- **TLS obligatorio**: certificados verificados en `~/.minio/certs/` (o el
  equivalente del contenedor). Poner `JABVOX_DRIVE_ENDPOINT=https://...` y
  `JABVOX_DRIVE_INSECURE_TLS=false`.
- **Cifrado en reposo**: habilitar KMS de MinIO (KES) y poner
  `JABVOX_DRIVE_SSE=aws:kms` + `JABVOX_DRIVE_SSE_KMS_KEY_ID=<key>` (o `AES256` con
  KMS habilitado). Documentar rotación de la clave maestra según KES.
- Actualización: `docker pull` del tag nuevo + recreate (dev); en prod, reemplazar
  binario/servicio en ventana de mantenimiento. MinIO es compatible hacia atrás
  entre releases cercanos; revisar las notas de cada release antes de saltar.

### 2.3 Provisión inicial de buckets y credenciales

```bash
mc alias set local http://127.0.0.1:9000 jabvox-admin '<secreto>'

# Buckets privados
mc mb --ignore-existing local/jabvox-drive
mc mb --ignore-existing local/jabvox-drive-overflow
mc anonymous set none local/jabvox-drive
mc anonymous set none local/jabvox-drive-overflow

# Credencial de EJECUCIÓN (privilegios mínimos sobre los 2 buckets del Drive)
cat > /tmp/drive-svc-policy.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
"Action":["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"],
"Resource":["arn:aws:s3:::jabvox-drive","arn:aws:s3:::jabvox-drive/*",
"arn:aws:s3:::jabvox-drive-overflow","arn:aws:s3:::jabvox-drive-overflow/*"]}]}
EOF
mc admin policy create local jabvox-drive-svc-policy /tmp/drive-svc-policy.json
mc admin user add local jabvox-drive-svc '<secreto-ejecucion>'
mc admin policy attach local jabvox-drive-svc-policy --user jabvox-drive-svc
rm -f /tmp/drive-svc-policy.json

# Identidad de APROVISIONAMIENTO (crea usuarios/policies por cuenta), separada del root
mc admin user add local jabvox-provisioner '<secreto-prov>'
```

**Aislamiento por prefijo por cuenta (endurecimiento, recomendado en prod):** para
cada cuenta se crea un usuario `svc-acct-<id>` con policy que solo permite
`acct-<id>/*` en ambos buckets, con `Condition StringLike s3:prefix`. Ejemplo
probado (una cuenta no puede leer ni listar el prefijo de otra → 403):

```json
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],
  "Resource":["arn:aws:s3:::jabvox-drive/acct-<id>/*","arn:aws:s3:::jabvox-drive-overflow/acct-<id>/*"]},
 {"Effect":"Allow","Action":["s3:ListBucket"],
  "Resource":["arn:aws:s3:::jabvox-drive","arn:aws:s3:::jabvox-drive-overflow"],
  "Condition":{"StringLike":{"s3:prefix":["acct-<id>/*"]}}}]}
```

---

## 3. Variables de entorno

Ver `.env.example` (bloque "jabvox-drive"). Nunca commitear valores reales.

| Variable | Uso |
|---|---|
| `JABVOX_DRIVE_ENDPOINT` | Endpoint S3 de MinIO (privado). |
| `JABVOX_DRIVE_REGION` | Región (p.ej. `us-east-1`). |
| `JABVOX_DRIVE_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` | Credencial de **ejecución**. |
| `JABVOX_DRIVE_BUCKET` / `_OVERFLOW_BUCKET` | Buckets principal y excedentes. |
| `JABVOX_DRIVE_PROVISIONER_ACCESS_KEY` / `_SECRET_KEY` | Credencial de **aprovisionamiento** (separada). |
| `JABVOX_DRIVE_INSECURE_TLS` | `true` solo en dev sin TLS verificado; **`false` en prod**. |
| `JABVOX_DRIVE_SSE` / `_SSE_KMS_KEY_ID` | Cifrado en reposo (KMS en prod). |
| `JABVOX_DRIVE_MAX_FILE_MB` | Tamaño máximo por archivo. |
| `JABVOX_DRIVE_MAX_CONCURRENT_UPLOADS` | Cargas concurrentes por cuenta. |

Para usar MinIO también como backend de Active Storage (adjuntos de mensajes):
`ACTIVE_STORAGE_SERVICE=s3_compatible` + bloque `STORAGE_*` (ya en storage.yml).

---

## 4. Puesta en marcha (dev)

```bash
# 1. MinIO arriba (sección 2.1) + buckets (2.3)
# 2. Migraciones
cd /ruta/jabvox
dotenv bundle exec rails db:migrate
# 3. App + workers
overmind start -f Procfile.dev    # backend + worker + vite
# (o: bin/rails s / bundle exec sidekiq -C config/sidekiq.yml / bin/vite dev)
```

El feature flag `jabvox_drive` por cuenta controla el módulo (columna
`accounts.jabvox_drive_enabled_jabvox`). Activar por cuenta en Super Admin o:
`Account.find(ID).update!(jabvox_drive_enabled_jabvox: true)`.

---

## 5. Cuotas y planes

El espacio contratado vive en el **plan** (`JabvoxPlan`, recurso `storage_gb`), que
el aprovisionamiento copia a `accounts.limits`. La cuota efectiva en bytes es
`account.storage_quota_bytes`. `storage_gb = 0` ⇒ ilimitado.

- Ver/editar por cuenta: Super Admin → cuenta → `limits.storage_gb`.
- Ver/editar por plan: Super Admin → planes → `limits.storage_gb` (included/extra).
- Al **ampliar** la cuota, encolar la regularización para traer de vuelta los
  excedentes que ya caben:
  `Jabvox::Drive::QuotaRegularizationJob.perform_later(account_id)`.

---

## 5b. Worker dedicado (aislado)

El Drive tiene su **propio worker Sidekiq**, aislado del resto (igual que CDR, media,
etc.), para que la ingesta de adjuntos a MinIO, la regularización de cuota y la
recuperación de la cola durable **no taponen los mensajes ni otros servicios**.

- Cola: `jabvox_drive` (NO está en `config/sidekiq.yml` principal → solo la procesa
  este worker).
- Config: `config/sidekiq_drive.yml` (concurrencia `JABVOX_DRIVE_CONCURRENCY`, default 5).
- systemd (prod): `deploy/workers/chatwoot-worker-drive.service`:
  ```bash
  sudo cp deploy/workers/chatwoot-worker-drive.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now chatwoot-worker-drive
  sudo systemctl status chatwoot-worker-drive
  ```
  Recordar: systemd NO recarga clases Ruby solo → reiniciar el servicio tras deploy.
- Dev (overmind): el proceso `drive_worker` ya está en `Procfile.dev`.
- El cron de recuperación (`jabvox_drive_pending_operation_retry_job`, cada 2 min)
  encola en la cola `jabvox_drive`, así que lo ejecuta este worker dedicado.

## 5c. IMPORTANTE tras desplegar

El Drive añade un initializer (`Account.prepend Jabvox::AccountDriveFeature`), modelos y
rutas nuevas. Los servicios systemd **no recargan clases Ruby solos**, así que tras el
deploy hay que **reiniciar web Y los workers** (incluido el del Drive); si no, el
`feature_enabled?('jabvox_drive')` falla con `undefined method 'feature_jabvox_drive?'`:

```bash
sudo systemctl restart chatwoot-web chatwoot-worker chatwoot-worker-drive
```
Y borrar `db/schema_cache.yml` tras migrar en consola remota.

## 6. Operación y diagnóstico

```bash
# Procesar operaciones pendientes ya mismo
bundle exec rake jabvox:drive:process_pending
# Reconciliar pg <-> MinIO (huérfanos) de una cuenta
bundle exec rake 'jabvox:drive:reconcile[ACCOUNT_ID]'
# Reencolar operaciones fallidas de una cuenta
bundle exec rake 'jabvox:drive:retry_failed[ACCOUNT_ID]'
```

Alertas a vigilar: cola de pendientes creciente, operaciones en `failed`,
`storage_over_quota?` recurrente, `available?` del StorageService en false.

---

## 7. Backup y restauración

**El bucket de excedentes NO es un backup** — es cuarentena por cuota. El backup
es independiente.

### Backup
```bash
# Replicación/espejo de todos los objetos a un destino de backup
mc mirror --overwrite --remove local/jabvox-drive        backup/jabvox-drive
mc mirror --overwrite --remove local/jabvox-drive-overflow backup/jabvox-drive-overflow
# Por empresa (prefijo):
mc mirror local/jabvox-drive/acct-<id>/ backup/jabvox-drive/acct-<id>/
# Versionado (recomendado en prod): mc version enable local/jabvox-drive
```
Backup de PostgreSQL (metadatos canónicos) con la rutina estándar de Jabvox — es
la fuente de verdad de las referencias; debe respaldarse junto con los objetos.

### Restauración
```bash
mc mirror backup/jabvox-drive        local/jabvox-drive
mc mirror backup/jabvox-drive-overflow local/jabvox-drive-overflow
# Tras restaurar, reconciliar para detectar divergencias pg<->MinIO:
bundle exec rake 'jabvox:drive:reconcile[ACCOUNT_ID]'
```

### Política de impago (excedentes)
Los objetos en `jabvox-drive-overflow` NO se borran automáticamente. Definir
periodo de gracia documentado y proceso auditable antes de cualquier purga.

---

## 8. Seguridad (checklist)

- [x] MinIO solo en red privada; buckets privados; sin políticas públicas.
- [x] Prefijo por cuenta + policy IAM por prefijo (aislamiento duro, probado).
- [x] App resuelve la cuenta desde la sesión; nunca de params del cliente.
- [x] Anti path-traversal en `object_key` (probado).
- [x] Descargas por Jabvox con permisos Pundit + presigned de vida corta +
      cabeceras seguras (`Content-Disposition`, `X-Content-Type-Options: nosniff`).
- [x] No se loguean tokens, URLs firmadas ni contenido.
- [ ] TLS verificado en prod (`JABVOX_DRIVE_INSECURE_TLS=false`).
- [ ] Cifrado en reposo con KMS (KES) + rotación documentada.
- [ ] (Opcional) Antivirus/escaneo de archivos si el entorno lo permite.
