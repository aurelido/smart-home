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

# Cargar librería de logging
source "$SCRIPT_DIR/lib/log.sh"
log_init "deploy"

# --- Verificaciones previas ---
check_prerequisites() {
    log_step "Verificando requisitos"

    if ! command -v docker &>/dev/null; then
        log_error "Docker no está instalado. Instalar Container Manager desde Package Center."
        exit 1
    fi
    log_debug "Docker encontrado: $(docker --version)"

    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose no disponible."
        exit 1
    fi
    log_debug "Docker Compose encontrado: $(docker compose version --short)"

    if [ ! -f "$PROJECT_DIR/.env" ]; then
        log_error "Archivo .env no encontrado."
        log_info "Ejecutar: cp .env.example .env y configurar los valores."
        exit 1
    fi
    log_debug "Archivo .env encontrado"

    log_info "Requisitos verificados ✓"
}

# --- Crear directorios necesarios ---
create_directories() {
    log_step "Creando directorios"
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

    log_step "Configurando contraseñas MQTT"

    # Cargar variables de entorno
    source "$PROJECT_DIR/.env"

    # Obtener imagen de Mosquitto del docker-compose.yml
    local MOSQUITTO_IMAGE
    MOSQUITTO_IMAGE=$(grep 'image:.*mosquitto' "$PROJECT_DIR/docker-compose.yml" | head -1 | awk '{print $2}')

    # Generar contraseñas usando docker run directamente
    # (docker compose run hereda el volumen :ro del compose file)
    docker run --rm \
        -v "$PROJECT_DIR/mosquitto/config:/mosquitto/config" \
        "$MOSQUITTO_IMAGE" \
        sh -c "
            mosquitto_passwd -c -b /mosquitto/config/password_file '${MQTT_USER_ZIGBEE2MQTT}' '${MQTT_PASSWORD_ZIGBEE2MQTT}' && \
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
    log_step "Descargando imágenes Docker"
    docker compose -f "$PROJECT_DIR/docker-compose.yml" pull
    log_info "Imágenes descargadas ✓"
}

# --- Iniciar servicios ---
start_services() {
    log_step "Iniciando servicios"
    docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
    log_info "Servicios iniciados ✓"
}

# --- Mostrar estado ---
show_status() {
    log_separator "Estado de los servicios"
    docker compose -f "$PROJECT_DIR/docker-compose.yml" ps
    log_separator "URLs de acceso"
    log_info "Home Assistant:  http://192.168.1.100:8123"
    log_info "Zigbee2MQTT:     http://192.168.1.100:8080"
    log_info "MQTT Broker:     192.168.1.100:1883"
    log_separator "Post-instalación"
    log_info "1. Acceder a Home Assistant y completar el asistente de configuración"
    log_info "2. Configurar la integración MQTT en Home Assistant"
    log_info "3. En Zigbee2MQTT, activar 'permit_join' para emparejar dispositivos"
    log_info "Log completo: $(log_file_path)"
}

# --- Ejecución principal ---
main() {
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
