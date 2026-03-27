#!/bin/bash
# =============================================================================
# Smart Home - Script de copia de seguridad
# =============================================================================
# Crea una copia de seguridad comprimida de toda la configuración y datos
# de estado del sistema domótico.
#
# Uso:
#   ./scripts/backup.sh              # Copia de seguridad estándar
#   ./scripts/backup.sh --no-prune   # Sin eliminar copias antiguas
#
# Programar en DSM:
#   Panel de Control → Programador de tareas → Crear →
#   Tarea programada → Script definido por el usuario
#   - Usuario: root
#   - Programación: Diaria, 03:00
#   - Script: bash /volume1/docker/smart-home/scripts/backup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/smarthome_backup_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=30

# Cargar librería de logging
source "$SCRIPT_DIR/lib/log.sh"
log_init "backup"

# --- Crear directorio de copias ---
mkdir -p "$BACKUP_DIR"

# --- Verificar espacio disponible ---
log_step "Verificando espacio disponible"
AVAILABLE_MB=$(df -m "$BACKUP_DIR" | awk 'NR==2 {print $4}')
log_debug "Espacio disponible: ${AVAILABLE_MB}MB"
if [ "$AVAILABLE_MB" -lt 500 ]; then
    log_warn "Espacio disponible bajo: ${AVAILABLE_MB}MB"
fi

# --- Crear copia de seguridad ---
log_step "Creando copia de seguridad"
log_info "Archivo: $(basename "$BACKUP_FILE")"

# Archivos y directorios a incluir
BACKUP_SOURCES=(
    # Configuración Docker
    "docker-compose.yml"
    ".env"

    # Mosquitto
    "mosquitto/config/"

    # Zigbee2MQTT (configuración + datos críticos)
    "zigbee2mqtt/data/configuration.yaml"
    "zigbee2mqtt/data/state.json"
    "zigbee2mqtt/data/database.db"
    "zigbee2mqtt/data/coordinator_backup.json"

    # Home Assistant (toda la configuración)
    "homeassistant/config/"

    # Scripts
    "scripts/"
)

# Construir lista de archivos existentes
EXISTING_SOURCES=()
for src in "${BACKUP_SOURCES[@]}"; do
    if [ -e "$PROJECT_DIR/$src" ]; then
        EXISTING_SOURCES+=("$src")
    else
        log_debug "No encontrado (omitido): $src"
    fi
done

# Crear tarball
tar -czf "$BACKUP_FILE" \
    -C "$PROJECT_DIR" \
    "${EXISTING_SOURCES[@]}" \
    2>/dev/null

# --- Verificar resultado ---
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log_info "Copia de seguridad creada: $BACKUP_SIZE"
else
    log_error "Error al crear la copia de seguridad"
    exit 1
fi

# --- Eliminar copias antiguas ---
if [ "${1:-}" != "--no-prune" ]; then
    log_step "Rotación de copias antiguas"
    DELETED=$(find "$BACKUP_DIR" -name "smarthome_backup_*.tar.gz" \
        -mtime "+${RETENTION_DAYS}" -delete -print | wc -l)
    if [ "$DELETED" -gt 0 ]; then
        log_info "Eliminadas $DELETED copias con más de ${RETENTION_DAYS} días"
    else
        log_debug "No hay copias antiguas que eliminar"
    fi
fi

# --- Resumen ---
TOTAL_BACKUPS=$(find "$BACKUP_DIR" -name "smarthome_backup_*.tar.gz" | wc -l)
log_info "Total de copias de seguridad: $TOTAL_BACKUPS"
log_info "Log completo: $(log_file_path)"
