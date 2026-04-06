# Casa Nórdica — Synology DS723+

Sistema domótico completo ejecutándose en un Synology DS723+ NAS. Todo gestionado como **Infraestructura como Código**: cada configuración, script y ajuste está documentado y versionado.

## Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│             Synology DS723+ (host network)              │
│                    192.168.1.100                        │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  Mosquitto   │  │ Zigbee2MQTT  │  │Home Assistant │  │
│  │  MQTT Broker │◄─┤   Bridge     │  │  Control Hub  │  │
│  │  :1883       │  │   :8080      │  │   :8123       │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘  │
│         │         MQTT     │                   │          │
│         └─────────────────┼───────────────────┘          │
│                           │                              │
│                    ┌──────┴───────┐                      │
│                    │   ZBT-2      │                      │
│                    │  USB-C/ACM0  │                      │
│                    └──────┬───────┘                      │
└───────────────────────────┼─────────────────────────────┘
                            │ Zigbee 3.0
              ┌─────────────┼─────────────┐
              │             │             │
         ┌────┴───┐   ┌────┴───┐   ┌─────┴────┐
         │ Philips │   │Sensores│   │  Enchufes │
         │  Hue    │   │  temp  │   │   smart   │
         └─────────┘   └────────┘   └──────────┘
```

Todos los contenedores usan `network_mode: host` para descubrimiento mDNS/SSDP.

## Servicios

| Servicio | Imagen | Puerto | Función |
|----------|--------|--------|---------|
| Mosquitto | `eclipse-mosquitto:2.0.21` | 1883, 9001 (WS) | Broker MQTT |
| Zigbee2MQTT | `ghcr.io/koenkk/zigbee2mqtt:2.1.1` | 8080 | Bridge Zigbee→MQTT |
| Home Assistant | `ghcr.io/home-assistant/home-assistant:2026.3` | 8123 | Centro de control |

## Inicio rápido

### 1. Preparar el NAS

```bash
# Conectar ZBT-2 al puerto USB del NAS (con cable extensor de 1m)
# Configurar tarea de arranque en DSM con scripts/synology-usb-setup.sh
# Instalar Container Manager desde Package Center
```

### 2. Clonar y configurar

```bash
# En el NAS vía SSH
git clone <repo-url> /volume1/docker/smart-home
cd /volume1/docker/smart-home
cp .env.example .env
```

### 3. Generar secretos

```bash
# Genera contraseñas MQTT + crea password_file + parchea Z2M config
bash scripts/generate-secrets.sh --apply
```

### 4. Desplegar

```bash
bash scripts/deploy.sh
```

### 5. Post-instalación

1. **Home Assistant** → `http://192.168.1.100:8123` — Completar asistente
2. **MQTT** → En HA: Ajustes → Integraciones → Añadir MQTT:
   - Broker: `192.168.1.100`, Puerto: `1883`
   - Usuario/contraseña: ver valores `MQTT_USER_HA`/`MQTT_PASS_HA` en `.env`
3. **Zigbee2MQTT** → `http://192.168.1.100:8080` — Emparejar dispositivos

## Estructura del proyecto

```
├── docker-compose.yml            # Stack de contenedores
├── .env.example                  # Plantilla de variables de entorno
├── mosquitto/config/             # Configuración del broker MQTT
├── zigbee2mqtt/data/             # Configuración y datos Zigbee
├── homeassistant/config/         # Configuración de Home Assistant
│   ├── automations.yaml          # Automatizaciones (recibidor, etc.)
│   ├── scenes.yaml               # Escenas
│   └── scripts.yaml              # Scripts de HA
├── scripts/
│   ├── lib/log.sh                # Librería de logging centralizada
│   ├── generate-secrets.sh       # Generador de contraseñas MQTT
│   ├── deploy.sh                 # Despliegue completo
│   ├── backup.sh                 # Copia de seguridad
│   ├── rollback.sh               # Rollback
│   ├── maintenance.sh            # Mantenimiento
│   ├── cleanup.sh                # Limpieza
│   └── synology-usb-setup.sh     # Drivers USB (tarea arranque DSM)
└── docs/
    ├── SETUP.md                  # Guía de instalación
    ├── SECURITY.md               # Política de seguridad
    ├── BACKUP.md                 # Estrategia de backups
    └── DEVICES.md                # Inventario de dispositivos
```

## Hardware

- **NAS**: Synology DS723+ (AMD Ryzen R1600, 2GB DDR4 ECC)
- **Coordinador Zigbee**: Home Assistant Connect ZBT-2 (Silicon Labs MG24, ember, 460800 baud)
- **Red**: ZTE router en modo bridge, NAS con IP estática 192.168.1.100

## Documentación

- [Guía de instalación completa](docs/SETUP.md)
- [Política de seguridad](docs/SECURITY.md)
- [Estrategia de copias de seguridad](docs/BACKUP.md)
- [Inventario de dispositivos](docs/DEVICES.md)

## Operaciones comunes

```bash
# Generar/regenerar contraseñas
bash scripts/generate-secrets.sh --apply --force

# Desplegar
bash scripts/deploy.sh

# Copia de seguridad manual
bash scripts/backup.sh

# Rollback
bash scripts/rollback.sh

# Ver logs
docker compose logs -f zigbee2mqtt
docker compose logs -f homeassistant
docker compose logs -f mosquitto
```
