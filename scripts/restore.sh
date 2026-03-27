#!/bin/bash
# =============================================================================
# Smart Home - Script de restauración
# =============================================================================
# Restaura el sistema desde una copia de seguridad.
#
# Uso:
#   ./scripts/restore.sh                                      # Restaurar última copia
#   ./scripts/restore.sh backups/smarthome_backup_XXXX.tar.gz # Restaurar copia específica
#
# ADVERTENCIA: Este script detendrá todos los contenedores y
# sobrescribirá la configuración actual.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Determinar archivo de copia de seguridad ---
if [ -n "${1:-}" ]; then
    BACKUP_FILE="$1"
    # Convertir ruta relativa a absoluta
    if [[ "$BACKUP_FILE" != /* ]]; then
        BACKUP_FILE="$PROJECT_DIR/$BACKUP_FILE"
    fi
else
    # Buscar la copia más reciente
    BACKUP_FILE=$(find "$BACKUP_DIR" -name "smarthome_backup_*.tar.gz" \
        -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

    if [ -z "$BACKUP_FILE" ]; then
        log_error "No se encontraron copias de seguridad en $BACKUP_DIR"
        exit 1
    fi
fi

# --- Verificaciones ---
if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Archivo no encontrado: $BACKUP_FILE"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
BACKUP_DATE=$(stat -c %y "$BACKUP_FILE" 2>/dev/null || stat -f %Sm "$BACKUP_FILE" 2>/dev/null)

echo "============================================="
echo "  Smart Home - Restauración"
echo "============================================="
echo ""
echo "  Archivo:  $(basename "$BACKUP_FILE")"
echo "  Tamaño:   $BACKUP_SIZE"
echo "  Fecha:    $BACKUP_DATE"
echo ""
log_warn "Esto detendrá todos los servicios y sobrescribirá la configuración actual."
echo ""

read -p "¿Continuar con la restauración? (s/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    log_info "Restauración cancelada."
    exit 0
fi

# --- Crear copia de seguridad de emergencia ---
log_info "Creando copia de seguridad de emergencia de la configuración actual..."
EMERGENCY_BACKUP="$BACKUP_DIR/emergency_pre_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$EMERGENCY_BACKUP" \
    -C "$PROJECT_DIR" \
    docker-compose.yml \
    mosquitto/config/ \
    zigbee2mqtt/data/configuration.yaml \
    homeassistant/config/configuration.yaml \
    2>/dev/null || true
log_info "Copia de emergencia: $(basename "$EMERGENCY_BACKUP")"

# --- Detener servicios ---
log_info "Deteniendo servicios..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" down 2>/dev/null || true

# --- Restaurar ---
log_info "Restaurando desde copia de seguridad..."
tar -xzf "$BACKUP_FILE" -C "$PROJECT_DIR"
log_info "Archivos restaurados ✓"

# --- Reiniciar servicios ---
log_info "Iniciando servicios..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d

# --- Verificar ---
echo ""
log_info "=== Estado de los servicios ==="
sleep 5
docker compose -f "$PROJECT_DIR/docker-compose.yml" ps
echo ""
log_info "Restauración completada."
log_info "Verificar que todos los servicios funcionan correctamente."
