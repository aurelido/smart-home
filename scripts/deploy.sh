#!/bin/bash
# =============================================================================
# Smart Home - Script de despliegue
# =============================================================================
# Uso:
#   ./scripts/deploy.sh          # Despliegue completo (primer uso)
#   ./scripts/deploy.sh update   # Solo actualizar contenedores
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Verificaciones previas ---
check_prerequisites() {
    log_info "Verificando requisitos..."

    if ! command -v docker &>/dev/null; then
        log_error "Docker no está instalado. Instalar Container Manager desde Package Center."
        exit 1
    fi

    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose no disponible."
        exit 1
    fi

    if [ ! -f "$PROJECT_DIR/.env" ]; then
        log_error "Archivo .env no encontrado."
        log_info "Ejecutar: cp .env.example .env y configurar los valores."
        exit 1
    fi

    log_info "Requisitos verificados ✓"
}

# --- Crear directorios necesarios ---
create_directories() {
    log_info "Creando directorios..."
    mkdir -p "$PROJECT_DIR/backups"
    mkdir -p "$PROJECT_DIR/homeassistant/config/themes"
    log_info "Directorios creados ✓"
}

# --- Configurar contraseñas MQTT ---
setup_mqtt_passwords() {
    local PASSWORD_FILE="$PROJECT_DIR/mosquitto/config/password_file"

    if [ -f "$PASSWORD_FILE" ]; then
        log_warn "El archivo de contraseñas MQTT ya existe. Omitiendo."
        return
    fi

    log_info "Configurando contraseñas MQTT..."

    # Cargar variables de entorno
    source "$PROJECT_DIR/.env"

    # Crear archivo de contraseñas temporal
    touch "$PASSWORD_FILE"

    # Iniciar Mosquitto temporalmente para generar contraseñas
    docker compose -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "$PASSWORD_FILE:/mosquitto/config/password_file" \
        --entrypoint sh mosquitto -c "
            mosquitto_passwd -b /mosquitto/config/password_file '${MQTT_USER_ZIGBEE2MQTT}' '${MQTT_PASSWORD_ZIGBEE2MQTT}' && \
            mosquitto_passwd -b /mosquitto/config/password_file '${MQTT_USER_HOMEASSISTANT}' '${MQTT_PASSWORD_HOMEASSISTANT}'
        "

    if [ -s "$PASSWORD_FILE" ]; then
        chmod 600 "$PASSWORD_FILE"
        log_info "Contraseñas MQTT configuradas ✓"
    else
        log_error "Error al crear contraseñas MQTT."
        exit 1
    fi
}

# --- Descargar imágenes ---
pull_images() {
    log_info "Descargando imágenes Docker..."
    docker compose -f "$PROJECT_DIR/docker-compose.yml" pull
    log_info "Imágenes descargadas ✓"
}

# --- Iniciar servicios ---
start_services() {
    log_info "Iniciando servicios..."
    docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
    log_info "Servicios iniciados ✓"
}

# --- Mostrar estado ---
show_status() {
    echo ""
    log_info "=== Estado de los servicios ==="
    docker compose -f "$PROJECT_DIR/docker-compose.yml" ps
    echo ""
    log_info "=== URLs de acceso ==="
    echo "  Home Assistant:  http://192.168.1.100:8123"
    echo "  Zigbee2MQTT:     http://192.168.1.100:8080"
    echo "  MQTT Broker:     192.168.1.100:1883"
    echo ""
    log_info "Tras el primer arranque:"
    echo "  1. Acceder a Home Assistant y completar el asistente de configuración"
    echo "  2. Configurar la integración MQTT en Home Assistant"
    echo "  3. En Zigbee2MQTT, activar 'permit_join' para emparejar dispositivos"
    echo ""
}

# --- Ejecución principal ---
main() {
    echo "============================================="
    echo "  Smart Home - Despliegue"
    echo "============================================="
    echo ""

    check_prerequisites

    if [ "${1:-}" = "update" ]; then
        log_info "Modo: actualización"
        pull_images
        start_services
    else
        log_info "Modo: despliegue completo"
        create_directories
        pull_images
        setup_mqtt_passwords
        start_services
    fi

    show_status
}

main "$@"
