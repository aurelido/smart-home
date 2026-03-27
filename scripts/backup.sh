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
LOG_FILE="$BACKUP_DIR/backup.log"

# Colores (solo si hay terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; NC=''
fi

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_warn() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') - AVISO: $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Crear directorio de copias ---
mkdir -p "$BACKUP_DIR"

log "=== Iniciando copia de seguridad ==="

# --- Verificar espacio disponible ---
AVAILABLE_MB=$(df -m "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_MB" -lt 500 ]; then
    log_warn "Espacio disponible bajo: ${AVAILABLE_MB}MB"
fi

# --- Crear copia de seguridad ---
log "Creando archivo: $(basename "$BACKUP_FILE")"

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
        log_warn "No encontrado (omitido): $src"
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
    log "Copia de seguridad creada: $BACKUP_SIZE"
else
    log_error "Error al crear la copia de seguridad"
    exit 1
fi

# --- Eliminar copias antiguas ---
if [ "${1:-}" != "--no-prune" ]; then
    log "Eliminando copias de seguridad con más de ${RETENTION_DAYS} días..."
    DELETED=$(find "$BACKUP_DIR" -name "smarthome_backup_*.tar.gz" \
        -mtime "+${RETENTION_DAYS}" -delete -print | wc -l)
    if [ "$DELETED" -gt 0 ]; then
        log "Eliminadas $DELETED copias antiguas"
    fi
fi

# --- Resumen ---
TOTAL_BACKUPS=$(find "$BACKUP_DIR" -name "smarthome_backup_*.tar.gz" | wc -l)
log "Total de copias de seguridad: $TOTAL_BACKUPS"
log "=== Copia de seguridad completada ==="
