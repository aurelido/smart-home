#!/bin/bash
# =============================================================================
# Synology DS723+ - Carga de drivers USB para Zigbee
# =============================================================================
# Este script debe ejecutarse como root en cada arranque del NAS.
#
# Configuración en DSM:
#   Panel de Control → Programador de tareas → Crear →
#   Tarea activada → Script definido por el usuario
#   - Usuario: root
#   - Evento: Arranque
#   - Script: bash /volume1/docker/smart-home/scripts/synology-usb-setup.sh
#
# Hardware: Home Assistant Connect ZBT-2 (Silicon Labs MG24, USB-C)
# Arquitectura NAS: AMD Ryzen R1600 (r1000 / x86_64)
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/zigbee-usb-setup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "=== Iniciando configuración USB Zigbee ==="

# --- Cargar módulos del kernel para dispositivos USB serie ---
MODULES=("usbserial" "ftdi_sio" "cdc-acm")

for mod in "${MODULES[@]}"; do
    if lsmod | grep -q "^${mod}"; then
        log "Módulo '$mod' ya cargado"
    else
        if modprobe "$mod" 2>/dev/null; then
            log "Módulo '$mod' cargado correctamente"
        else
            log "AVISO: No se pudo cargar el módulo '$mod' (puede que no sea necesario)"
        fi
    fi
done

# --- Esperar a que el dispositivo aparezca ---
sleep 3

# --- Configurar permisos del dispositivo ---
DEVICE_PATH="/dev/ttyACM0"
FALLBACK_PATH="/dev/ttyUSB0"

if [ -e "$DEVICE_PATH" ]; then
    chmod 666 "$DEVICE_PATH"
    log "Permisos configurados para $DEVICE_PATH"
elif [ -e "$FALLBACK_PATH" ]; then
    chmod 666 "$FALLBACK_PATH"
    log "Dispositivo encontrado en ruta alternativa: $FALLBACK_PATH"
    log "IMPORTANTE: Actualizar ZIGBEE_ADAPTER_PATH en .env"
else
    log "ERROR: No se encontró el adaptador Zigbee en $DEVICE_PATH ni $FALLBACK_PATH"
    log "Verificar conexión USB del ZBT-2 y ejecutar: dmesg | grep tty"
    exit 1
fi

# --- Verificación ---
log "Dispositivos USB serie disponibles:"
ls -la /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | tee -a "$LOG_FILE" || true

log "=== Configuración USB completada ==="
