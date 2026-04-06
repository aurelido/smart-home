# Guía de instalación completa

Instrucciones paso a paso para configurar el sistema domótico desde cero en el Synology DS723+.

## Requisitos previos

### Hardware

- Synology DS723+ con DSM 7.x instalado
- Home Assistant Connect ZBT-2 (firmware Zigbee instalado)
- Cable extensor USB de 1 metro (USB-A a USB-C)
- Cable Ethernet conectado al router
- Al menos un disco duro instalado con un volumen creado

### Red

- NAS con IP estática: `192.168.1.100`
  - Configurar en: Panel de Control → Red → Interfaz de red → Editar → IPv4 → Manual
- Router ZTE en modo bridge
- Acceso SSH habilitado temporalmente

## Paso 1: Configurar el NAS

### 1.1 Habilitar SSH

1. Panel de Control → Terminal y SNMP → Terminal
2. Activar "Habilitar servicio SSH"
3. Puerto: 22 (por defecto)

### 1.2 Instalar Container Manager

1. Package Center → buscar "Container Manager"
2. Instalar

### 1.3 Conectar el adaptador ZBT-2

1. Conectar el cable extensor USB al puerto USB 3.2 del NAS (frontal)
2. Conectar el ZBT-2 al otro extremo del cable extensor
3. **Importante**: Mantener el ZBT-2 alejado del NAS (mínimo 50cm) para evitar interferencias USB 3.0 con Zigbee

### 1.4 Configurar drivers USB (tarea de arranque)

1. Panel de Control → Programador de tareas
2. Crear → Tarea activada → Script definido por el usuario
3. Configurar:
   - **General**: Nombre = "Zigbee USB Setup", Usuario = root
   - **Condición de la tarea**: Evento = Arranque
   - **Configuración de la tarea**: Script definido por el usuario:

```bash
bash /volume1/docker/smart-home/scripts/synology-usb-setup.sh
```

4. Ejecutar la tarea manualmente la primera vez
5. Verificar que el dispositivo aparece:

```bash
# SSH al NAS
ssh admin@192.168.1.100
sudo dmesg | grep tty
# Debe aparecer algo como: cdc_acm 1-1:1.0: ttyACM0: USB ACM device
ls -la /dev/ttyACM0
```

## Paso 2: Desplegar el sistema

### 2.1 Clonar el repositorio

```bash
ssh admin@192.168.1.100
sudo mkdir -p /volume1/docker
cd /volume1/docker
git clone <url-del-repositorio> smart-home
cd smart-home
```

### 2.2 Configurar secretos

```bash
cp .env.example .env

# Generar contraseñas MQTT automáticamente + crear password_file + parchear Z2M
bash scripts/generate-secrets.sh --apply
```

Esto genera contraseñas aleatorias para dos usuarios MQTT:
- `MQTT_USER_Z2M` / `MQTT_PASS_Z2M` — usado por Zigbee2MQTT
- `MQTT_USER_HA` / `MQTT_PASS_HA` — usado por Home Assistant

Verificar también en `.env`:
- `Z2M_DEVICE=/dev/ttyACM0` (ruta del adaptador ZBT-2)
- `HOST_IP=192.168.1.100`

### 2.3 Ejecutar despliegue

```bash
bash scripts/deploy.sh
```

El script:
1. Verifica requisitos (Docker, .env, credenciales MQTT)
2. Crea directorios necesarios
3. Genera configuraciones por defecto (si no existen)
4. Genera archivo de contraseñas MQTT (si no existe)
5. Inyecta credenciales en la configuración de Z2M
6. Verifica el dispositivo Zigbee
7. Crea backup pre-despliegue
8. Descarga imágenes y arranca los contenedores

## Paso 3: Configuración inicial

### 3.1 Home Assistant

1. Abrir `http://192.168.1.100:8123`
2. Completar el asistente de configuración:
   - Crear cuenta de administrador
   - Configurar ubicación (coordenadas, zona horaria)
   - Seleccionar integraciones detectadas
3. Configurar integración MQTT:
   - Ajustes → Dispositivos y servicios → Añadir integración → MQTT
   - Broker: `192.168.1.100`
   - Puerto: `1883`
   - Usuario: valor de `MQTT_USER_HA` en `.env`
   - Contraseña: valor de `MQTT_PASS_HA` en `.env`

### 3.2 Zigbee2MQTT

1. Abrir `http://192.168.1.100:8080`
2. Verificar que el estado del bridge es "online"
3. Para emparejar la bombilla Philips Hue:
   - Activar "Permit join" (botón superior)
   - Resetear la bombilla Hue (encender y apagar 5 veces rápidamente)
   - Esperar a que aparezca en la lista de dispositivos
   - Desactivar "Permit join"
   - Renombrar el dispositivo: "Luz Recibidor"

### 3.3 Integraciones adicionales

- **Xiaomi TV Box S**: En HA → Integraciones → Android TV Remote (detección automática por red)
- **Bosch Washer**: En HA → Integraciones → Home Connect (requiere cuenta Bosch y autorización OAuth)

## Paso 4: Configurar copias de seguridad

1. Panel de Control → Programador de tareas
2. Crear → Tarea programada → Script definido por el usuario
3. Configurar:
   - **General**: Nombre = "Smart Home Backup", Usuario = root
   - **Programación**: Diaria, 03:00
   - **Configuración de la tarea**:

```bash
bash /volume1/docker/smart-home/scripts/backup.sh
```

## Paso 5: Seguridad post-instalación

1. **Deshabilitar SSH** si no se necesita permanentemente:
   - Panel de Control → Terminal y SNMP → Desactivar SSH
2. **Activar auth_token en Zigbee2MQTT**:
   - Editar `zigbee2mqtt/data/configuration.yaml`
   - Descomentar y configurar `auth_token` en la sección `frontend`
   - Reiniciar: `docker compose restart zigbee2mqtt`
3. **Configurar firewall del NAS**:
   - Panel de Control → Seguridad → Cortafuegos
   - Permitir solo IPs de la red local (192.168.1.0/24)

## Verificación

Comprobar que todo funciona:

```bash
# Estado de contenedores
docker compose ps

# Logs de Zigbee2MQTT
docker compose logs zigbee2mqtt --tail 20

# Test MQTT
docker exec mosquitto mosquitto_sub -h localhost -t 'zigbee2mqtt/bridge/state' -C 1 -u zigbee2mqtt -P <contraseña>

# Dispositivos Zigbee emparejados
docker exec mosquitto mosquitto_sub -h localhost -t 'zigbee2mqtt/bridge/devices' -C 1 -u zigbee2mqtt -P <contraseña>
```

## Resolución de problemas

### El ZBT-2 no se detecta

```bash
# Verificar módulos del kernel
sudo lsmod | grep cdc_acm
# Si no aparece:
sudo modprobe cdc-acm

# Verificar dispositivo USB
sudo lsusb
sudo dmesg | grep -i "acm\|usb\|nabu"
```

### Zigbee2MQTT no arranca

```bash
# Ver logs detallados
docker compose logs zigbee2mqtt

# Errores comunes:
# "No such file or directory /dev/ttyACM0" → Verificar drivers USB y Z2M_DEVICE en .env
# "MQTT connection refused" → Verificar que Mosquitto está corriendo
# "Not authorized" → Credenciales MQTT no coinciden. Regenerar:
#   bash scripts/generate-secrets.sh --apply --force
# "Failed to start EZSP" → Verificar adapter: ember, baudrate: 460800 en Z2M config
```

### Home Assistant no conecta al MQTT

1. Con `network_mode: host`, usar `192.168.1.100:1883` como broker (no nombre de contenedor)
2. Verificar usuario/contraseña: usar `MQTT_USER_HA`/`MQTT_PASS_HA` de `.env`
3. Regenerar si es necesario: `bash scripts/generate-secrets.sh --apply --force`
