# Casa Inteligente — Synology DS723+

Sistema domótico completo ejecutándose en un Synology DS723+ NAS. Todo gestionado como **Infraestructura como Código**: cada configuración, script y ajuste está documentado y versionado.

## Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│                   Synology DS723+                       │
│                  192.168.1.100                          │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  Mosquitto   │  │ Zigbee2MQTT  │  │Home Assistant │  │
│  │  MQTT Broker │◄─┤   Bridge     │  │  Control Hub  │  │
│  │  :1883       │  │   :8080      │  │   :8123       │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘  │
│         │                 │                   │          │
│         └────── smarthome network ────────────┘          │
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

## Servicios

| Servicio | Imagen | Puerto | Función |
|----------|--------|--------|---------|
| Mosquitto | `eclipse-mosquitto:2.0.21` | 1883 | Broker MQTT |
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

# Configurar secretos
cp .env.example .env
nano .env  # Establecer contraseñas reales
```

### 3. Desplegar

```bash
./scripts/deploy.sh
```

### 4. Post-instalación

1. **Home Assistant** → `http://192.168.1.100:8123` — Completar asistente
2. **MQTT** → En HA: Ajustes → Integraciones → Añadir MQTT → `192.168.1.100:1883`
3. **Zigbee2MQTT** → `http://192.168.1.100:8080` — Activar emparejamiento

## Estructura del proyecto

```
├── docker-compose.yml          # Stack de contenedores
├── .env.example                # Plantilla de secretos
├── mosquitto/config/           # Configuración del broker MQTT
├── zigbee2mqtt/data/           # Configuración y datos Zigbee
├── homeassistant/config/       # Configuración de Home Assistant
├── scripts/
│   ├── synology-usb-setup.sh   # Drivers USB (tarea de arranque DSM)
│   ├── deploy.sh               # Despliegue completo
│   ├── backup.sh               # Copia de seguridad diaria
│   └── restore.sh              # Restauración desde backup
└── docs/
    ├── SETUP.md                # Guía de instalación completa
    ├── SECURITY.md             # Política de seguridad
    ├── BACKUP.md               # Estrategia de copias de seguridad
    └── DEVICES.md              # Inventario de dispositivos
```

## Hardware

- **NAS**: Synology DS723+ (AMD Ryzen R1600, 2GB DDR4 ECC)
- **Coordinador Zigbee**: Home Assistant Connect ZBT-2 (Silicon Labs MG24)
- **Red**: ZTE router en modo bridge, NAS con IP estática 192.168.1.100

## Documentación

- [Guía de instalación completa](docs/SETUP.md)
- [Política de seguridad](docs/SECURITY.md)
- [Estrategia de copias de seguridad](docs/BACKUP.md)
- [Inventario de dispositivos](docs/DEVICES.md)

## Operaciones comunes

```bash
# Actualizar contenedores
./scripts/deploy.sh update

# Copia de seguridad manual
./scripts/backup.sh

# Restaurar desde backup
./scripts/restore.sh

# Ver logs
docker compose logs -f zigbee2mqtt
docker compose logs -f homeassistant
docker compose logs -f mosquitto

# Emparejar nuevo dispositivo Zigbee (activar temporalmente)
docker exec zigbee2mqtt sh -c \
  'mosquitto_pub -h mosquitto -t zigbee2mqtt/bridge/request/permit_join -m '"'"'{"value":true,"time":120}'"'"
```
