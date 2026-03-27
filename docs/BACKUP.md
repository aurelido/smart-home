# Estrategia de copias de seguridad

## Resumen

| Aspecto | Valor |
|---------|-------|
| Frecuencia | Diaria, 03:00 |
| Retención | 30 días |
| Destino primario | `/volume1/docker/smart-home/backups/` |
| Formato | `.tar.gz` (tarball comprimido) |
| Automatización | DSM Task Scheduler |

## Qué se incluye en el backup

### Archivos críticos (prioridad máxima)

| Archivo | Descripción | Impacto si se pierde |
|---------|-------------|----------------------|
| `zigbee2mqtt/data/coordinator_backup.json` | Clave de red Zigbee + datos de emparejamiento | Hay que re-emparejar TODOS los dispositivos |
| `zigbee2mqtt/data/database.db` | Base de datos de dispositivos | Pérdida de nombres y configuración de dispositivos |
| `.env` | Contraseñas y tokens | Hay que regenerar todos los secretos |
| `mosquitto/config/password_file` | Contraseñas MQTT hasheadas | Hay que regenerar contraseñas MQTT |

### Archivos importantes

| Archivo/Directorio | Descripción |
|--------------------|-------------|
| `docker-compose.yml` | Definición del stack (también en git) |
| `mosquitto/config/mosquitto.conf` | Configuración del broker (también en git) |
| `zigbee2mqtt/data/configuration.yaml` | Configuración Z2M (con claves generadas) |
| `zigbee2mqtt/data/state.json` | Estados actuales de dispositivos |
| `homeassistant/config/` | Toda la configuración de HA |
| `homeassistant/config/.storage/` | Integraciones, dashboards, entidades |
| `scripts/` | Scripts operacionales (también en git) |

## Uso

### Copia de seguridad manual

```bash
cd /volume1/docker/smart-home
./scripts/backup.sh
```

### Copia sin eliminar antiguas

```bash
./scripts/backup.sh --no-prune
```

### Restauración (última copia)

```bash
./scripts/restore.sh
```

### Restauración (copia específica)

```bash
./scripts/restore.sh backups/smarthome_backup_20260326_030000.tar.gz
```

### Verificar contenido de un backup

```bash
tar -tzf backups/smarthome_backup_XXXXXXXX_XXXXXX.tar.gz
```

## Programación automática

### Configurar en DSM

1. Panel de Control → Programador de tareas
2. Crear → Tarea programada → Script definido por el usuario
3. **General**: Nombre = "Smart Home Backup", Usuario = root
4. **Programación**: Diaria, 03:00
5. **Configuración de la tarea**:

```bash
bash /volume1/docker/smart-home/scripts/backup.sh
```

6. Opcional: Habilitar notificación por email en caso de error

## Destinos adicionales recomendados

### Opción 1: Synology Hyper Backup (recomendado)

Crear una tarea de Hyper Backup adicional que copie el directorio `backups/` a:
- Disco USB externo conectado al NAS
- Synology C2 Storage (cloud cifrado)
- Otro NAS Synology en red

### Opción 2: Copia manual a USB

```bash
# Conectar disco USB al NAS
cp /volume1/docker/smart-home/backups/smarthome_backup_*.tar.gz /volumeUSB1/usbshare/backups/
```

## Proceso de restauración completa (desde cero)

Si el NAS se reinicia completamente o se reemplaza:

1. Instalar DSM y Container Manager
2. Configurar IP estática: `192.168.1.100`
3. Conectar ZBT-2 y configurar drivers USB (tarea de arranque)
4. Clonar el repositorio git
5. Copiar el backup más reciente al directorio `backups/`
6. Ejecutar restauración:

```bash
cd /volume1/docker/smart-home
./scripts/restore.sh backups/smarthome_backup_XXXXXXXX.tar.gz
```

7. Verificar servicios: `docker compose ps`
8. Comprobar que los dispositivos Zigbee se reconectan automáticamente

**Tiempo estimado de recuperación**: 30-60 minutos (sin contar la instalación de DSM).

## Monitorización

Verificar que los backups se ejecutan correctamente:

```bash
# Último backup creado
ls -lt backups/smarthome_backup_*.tar.gz | head -1

# Log de backups
cat backups/backup.log | tail -20

# Número total de backups
ls backups/smarthome_backup_*.tar.gz | wc -l
```
