# Política de seguridad

## Principios

1. **Local primero**: Todo el procesamiento se realiza en la red local, sin dependencias cloud para funciones core
2. **Mínimo privilegio**: Cada servicio tiene solo los permisos necesarios
3. **Defensa en profundidad**: Múltiples capas de seguridad
4. **Secretos fuera del código**: Ningún secreto se almacena en el repositorio git

## Control de acceso

### Mosquitto MQTT

- Autenticación obligatoria (`allow_anonymous false`)
- Usuarios separados por servicio con contraseñas independientes:
  - `MQTT_USER_Z2M` (por defecto: `zigbee2mqtt`) — usado por Zigbee2MQTT
  - `MQTT_USER_HA` (por defecto: `homeassistant`) — usado por Home Assistant
- Contraseñas generadas automáticamente con `scripts/generate-secrets.sh`
- Archivo de contraseñas hasheado con `mosquitto_passwd` (PBKDF2)
- Archivo de contraseñas con permisos `644` (Mosquitto necesita leerlo)

### Zigbee2MQTT

- Panel web protegido con `auth_token` (configurar tras el primer arranque)
- `permit_join: false` por defecto — solo activar temporalmente para emparejar
- Claves de red Zigbee generadas automáticamente y únicas

### Home Assistant

- Autenticación de usuarios integrada (creada durante el asistente inicial)
- Protección contra fuerza bruta:
  - `ip_ban_enabled: true`
  - `login_attempts_threshold: 5`
  - IPs baneadas tras 5 intentos fallidos
- Sesiones con tokens JWT

## Seguridad de red

### Aislamiento

- Todos los servicios usan `network_mode: host` (necesario para descubrimiento mDNS/SSDP)
- No se expone ningún puerto a Internet (router sin port forwarding)
- Comunicación MQTT vía localhost (192.168.1.100:1883)

### Firewall del NAS

Configurar en Panel de Control → Seguridad → Cortafuegos:

| Puerto | Servicio | Acceso permitido |
|--------|----------|-------------------|
| 8123 | Home Assistant | 192.168.1.0/24 |
| 8080 | Zigbee2MQTT | 192.168.1.0/24 |
| 1883 | MQTT | 192.168.1.0/24 |
| 5000/5001 | DSM | 192.168.1.0/24 |
| 22 | SSH | Solo cuando sea necesario |
| Todos | — | Denegar por defecto |

## Seguridad de contenedores

### Imágenes

- Todas las imágenes con versión fija (no se usa `:latest`)
- Imágenes oficiales únicamente:
  - `eclipse-mosquitto` (Eclipse Foundation)
  - `ghcr.io/koenkk/zigbee2mqtt` (Koenkk / GitHub Container Registry)
  - `ghcr.io/home-assistant/home-assistant` (Nabu Casa / GitHub Container Registry)

### Ejecución

- `restart: unless-stopped` en todos los contenedores
- Volúmenes de solo lectura donde es posible (`/run/udev:ro`, `/etc/localtime:ro`)
- Límites de memoria configurados para cada contenedor
- Dispositivos USB: solo se pasa el dispositivo específico (`/dev/ttyACM0`), no `/dev` completo
- Contenedores sin `user: PUID:PGID` — usan sus usuarios internos por defecto

## Gestión de secretos

### Qué es secreto

| Secreto | Ubicación | Gitignored |
|---------|-----------|------------|
| Contraseñas MQTT (MQTT_PASS_Z2M, MQTT_PASS_HA) | `.env` | ✅ |
| Password file MQTT | `mosquitto/config/password_file` | ✅ |
| Secrets HA | `homeassistant/config/secrets.yaml` | ✅ |
| Clave red Zigbee | `zigbee2mqtt/data/configuration.yaml` (generada) | Parcial* |

*\* El archivo `configuration.yaml` de Zigbee2MQTT se versiona con `GENERATE` como valor. Tras el primer arranque, Z2M reemplaza GENERATE con la clave real. El archivo con la clave real se incluye en los backups pero no debe hacer commit al repositorio tras el primer arranque.*

### Flujo de secretos

1. Copiar `.env.example` → `.env`
2. Ejecutar `scripts/generate-secrets.sh --apply`:
   - Genera contraseñas aleatorias para `MQTT_PASS_Z2M` y `MQTT_PASS_HA`
   - Crea `mosquitto/config/password_file` con ambos usuarios
   - Inyecta credenciales en `zigbee2mqtt/data/configuration.yaml`
3. `deploy.sh` verifica que las credenciales no son placeholders
4. Home Assistant usa credenciales `MQTT_USER_HA`/`MQTT_PASS_HA` configuradas en la UI

## Seguridad de datos

### Zigbee

- Clave de red única generada en el primer arranque
- Canal Zigbee 25 (minimiza interferencia con WiFi)
- `permit_join` desactivado por defecto
- Comunicación cifrada entre dispositivos Zigbee

### Backups

- Los backups incluyen archivos con secretos (`.env`, `password_file`)
- Almacenar los backups en ubicación segura
- Si se usa Hyper Backup a destino remoto, habilitar cifrado del lado del cliente

## Mejoras futuras

- [ ] MQTT sobre TLS (certificados autofirmados para comunicación interna)
- [ ] Proxy inverso con HTTPS (nginx/Caddy) para acceso web
- [ ] Autenticación Zigbee2MQTT vía proxy inverso
- [ ] Notificaciones de seguridad (intentos de acceso fallidos, dispositivos nuevos)
- [ ] Monitorización con Prometheus/Grafana
- [ ] VPN (WireGuard) para acceso remoto seguro

## Respuesta a incidentes

### Acceso no autorizado sospechado

1. Desconectar el NAS de la red
2. Revisar logs: `docker compose logs --since 24h`
3. Verificar usuarios HA: Ajustes → Personas
4. Regenerar todas las contraseñas: `bash scripts/generate-secrets.sh --apply --force`
5. Regenerar clave de red Zigbee si es necesario
6. Reiniciar: `bash scripts/deploy.sh`

### Dispositivo Zigbee comprometido

1. Eliminar el dispositivo desde Zigbee2MQTT
2. Reset de fábrica del dispositivo
3. Verificar que no hay dispositivos desconocidos en la red Zigbee
