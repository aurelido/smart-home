# Inventario de dispositivos

## Infraestructura

| Dispositivo | Ubicación | Conexión | IP/Protocolo | Notas |
|-------------|-----------|----------|--------------|-------|
| Synology DS723+ | Salón | Ethernet | 192.168.1.100 | Servidor principal |
| ZTE Router | — | — | 192.168.1.1 | Modo bridge |
| HA Connect ZBT-2 | Salón (en NAS) | USB 3.0 + extensor 1m | /dev/ttyACM0 | Coordinador Zigbee |

## Dispositivos actuales

### Philips Hue — Bombilla (Recibidor)

| Campo | Valor |
|-------|-------|
| Tipo | Iluminación Zigbee |
| Ubicación | Recibidor |
| Protocolo | Zigbee 3.0 |
| Integración | Zigbee2MQTT |
| Nombre amigable | `luz_recibidor` |
| Notas | Desvincular del bridge Hue antes de emparejar. Reset: encender/apagar 5 veces rápido |

### Xiaomi TV Box S (Salón)

| Campo | Valor |
|-------|-------|
| Tipo | Reproductor multimedia |
| Ubicación | Salón |
| Protocolo | WiFi / Android TV |
| Integración | Home Assistant — Android TV Remote |
| IP | Asignar IP estática en el router |
| Notas | Integración por red, no requiere Zigbee |

### Bosch Lavadora con Home Connect (Cocina)

| Campo | Valor |
|-------|-------|
| Tipo | Electrodoméstico inteligente |
| Ubicación | Cocina |
| Protocolo | WiFi / Cloud (Home Connect API) |
| Integración | Home Assistant — Home Connect |
| Notas | Requiere cuenta Bosch y autorización OAuth. Depende de cloud Bosch |

## Dispositivos planificados

### Fase 2 — Sensores y control básico

| Dispositivo | Ubicación | Protocolo | Uso previsto |
|-------------|-----------|-----------|--------------|
| Sensor de movimiento | Recibidor | Zigbee | Encender luz al detectar movimiento |
| Sensor de movimiento | Pasillo | Zigbee | Encender luz al detectar movimiento |
| Sensor de temperatura/humedad | Salón | Zigbee | Monitorización de clima interior |
| Sensor de temperatura/humedad | Dormitorio | Zigbee | Monitorización de clima interior |
| Enchufe inteligente | Cocina | Zigbee | Monitorización de consumo |
| Enchufe inteligente | Salón | Zigbee | Control TV / dispositivos |

### Fase 3 — Iluminación extendida

| Dispositivo | Ubicación | Protocolo | Uso previsto |
|-------------|-----------|-----------|--------------|
| Bombilla inteligente | Salón | Zigbee | Iluminación ambiental |
| Bombilla inteligente | Dormitorio | Zigbee | Luz nocturna / despertar gradual |
| Tira LED | Cocina | Zigbee | Iluminación bajo muebles |

### Fase 4 — Seguridad y avanzado

| Dispositivo | Ubicación | Protocolo | Uso previsto |
|-------------|-----------|-----------|--------------|
| Sensor de puerta/ventana | Entrada principal | Zigbee | Seguridad / automatización |
| Sensor de puerta/ventana | Ventanas | Zigbee | Seguridad |
| Cámara IP | Entrada | WiFi / RTSP | Vigilancia (Surveillance Station) |
| Sensor de fugas de agua | Cocina/Baño | Zigbee | Detección de fugas |
| Control por voz | Salón | WiFi | Comandos por voz (futuro) |

## Mapa de red Zigbee

```
                    ┌───────────┐
                    │  ZBT-2    │
                    │Coordinador│
                    └─────┬─────┘
                          │
                    ┌─────┴─────┐
                    │           │
              ┌─────┴───┐ ┌────┴────┐
              │   Luz    │ │Enchufes │  ← Routers (alimentados por red)
              │Recibidor │ │  Smart  │
              └─────┬────┘ └────┬────┘
                    │           │
              ┌─────┴───┐ ┌────┴────┐
              │Sensores  │ │Sensores │  ← End Devices (batería)
              │movimiento│ │  temp   │
              └──────────┘ └─────────┘
```

**Nota**: Los dispositivos alimentados por red (bombillas, enchufes) actúan como routers Zigbee, extendiendo el alcance de la red mesh. Colocar estratégicamente para asegurar buena cobertura.

## Marcas recomendadas compatibles

| Marca | Tipo de dispositivo | Compatibilidad Z2M |
|-------|--------------------|--------------------|
| Aqara | Sensores, interruptores | Excelente |
| IKEA TRÅDFRI | Bombillas, enchufes | Buena |
| Sonoff | Enchufes, sensores | Buena |
| Philips Hue | Iluminación | Excelente |
| Xiaomi | Sensores | Buena |
| MOES | Termostatos, interruptores | Buena |

Consultar dispositivos compatibles en: https://www.zigbee2mqtt.io/supported-devices/
