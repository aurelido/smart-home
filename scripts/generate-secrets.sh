#!/bin/bash
# =============================================================================
# GENERATE-SECRETS.SH - Generador de contraseñas seguras
# =============================================================================
# Genera contraseñas aleatorias para los servicios MQTT y las escribe en .env.
# Opcionalmente regenera el archivo de contraseñas de Mosquitto.
#
# Uso:
#   ./scripts/generate-secrets.sh            # Generar contraseñas en .env
#   ./scripts/generate-secrets.sh --apply    # Generar + crear password_file de Mosquitto
#   ./scripts/generate-secrets.sh --force    # Sobrescribir contraseñas existentes
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"
PASSWORD_FILE="${ROOT_DIR}/mosquitto/config/password_file"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Generar contraseña aleatoria ---
generate_password() {
    local length="${1:-32}"
    # Usar openssl si está disponible, si no /dev/urandom
    if command -v openssl &>/dev/null; then
        openssl rand -base64 "$length" | tr -d '/+=' | head -c "$length"
    else
        LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
    fi
}

# --- Actualizar o añadir variable en .env ---
set_env_var() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -q "^${key}=" "$file" 2>/dev/null; then
        # Reemplazar valor existente
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file"
        rm -f "${file}.bak"
    else
        # Añadir al final
        echo "${key}=${value}" >> "$file"
    fi
}

# --- Comprobar si una contraseña es un placeholder ---
is_placeholder() {
    local value="$1"
    case "$value" in
        ""|CAMBIAR_*|cambiar_*|CHANGE_ME*|__*__)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# --- Crear .env desde .env.example si no existe ---
ensure_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$ENV_EXAMPLE" ]]; then
            cp "$ENV_EXAMPLE" "$ENV_FILE"
            log_info "Creado .env desde .env.example"
        else
            log_error "No se encontró .env ni .env.example"
            exit 1
        fi
    fi
}

# --- Generar contraseñas MQTT ---
generate_mqtt_secrets() {
    local force="${1:-false}"

    log_info "Generando credenciales MQTT..."

    source "$ENV_FILE"

    # --- Zigbee2MQTT ---
    local current_z2m="${MQTT_PASS_Z2M:-}"
    if [[ "$force" == "true" ]] || is_placeholder "$current_z2m"; then
        local new_pass_z2m
        new_pass_z2m=$(generate_password 32)
        set_env_var "MQTT_PASS_Z2M" "$new_pass_z2m" "$ENV_FILE"
        log_success "MQTT_PASS_Z2M generada (usuario: ${MQTT_USER_Z2M:-zigbee2mqtt})"
    else
        log_info "MQTT_PASS_Z2M ya configurada. Usar --force para regenerar."
    fi

    # --- Home Assistant ---
    local current_ha="${MQTT_PASS_HA:-}"
    if [[ "$force" == "true" ]] || is_placeholder "$current_ha"; then
        local new_pass_ha
        new_pass_ha=$(generate_password 32)
        set_env_var "MQTT_PASS_HA" "$new_pass_ha" "$ENV_FILE"
        log_success "MQTT_PASS_HA generada (usuario: ${MQTT_USER_HA:-homeassistant})"
    else
        log_info "MQTT_PASS_HA ya configurada. Usar --force para regenerar."
    fi

    # Asegurar que los usuarios existen en .env
    set_env_var "MQTT_USER_Z2M" "${MQTT_USER_Z2M:-zigbee2mqtt}" "$ENV_FILE"
    set_env_var "MQTT_USER_HA" "${MQTT_USER_HA:-homeassistant}" "$ENV_FILE"
}

# --- Crear archivo de contraseñas de Mosquitto ---
apply_mqtt_passwords() {
    log_info "Creando archivo de contraseñas de Mosquitto..."

    # Recargar .env con las contraseñas recién generadas
    source "$ENV_FILE"

    local MOSQUITTO_IMAGE="${MQTT_IMAGE:-eclipse-mosquitto}:${MQTT_TAG:-2.0.21}"

    # Asegurar que el directorio existe
    mkdir -p "$(dirname "$PASSWORD_FILE")"

    # Eliminar archivo anterior
    rm -f "$PASSWORD_FILE"

    # Generar password_file con ambos usuarios
    docker run --rm \
        -v "$(dirname "$PASSWORD_FILE"):/mosquitto/config" \
        "$MOSQUITTO_IMAGE" \
        sh -c "
            mosquitto_passwd -c -b /mosquitto/config/password_file '${MQTT_USER_Z2M}' '${MQTT_PASS_Z2M}' && \
            mosquitto_passwd -b /mosquitto/config/password_file '${MQTT_USER_HA}' '${MQTT_PASS_HA}'
        "

    if [[ -s "$PASSWORD_FILE" ]]; then
        chmod 644 "$PASSWORD_FILE" 2>/dev/null || log_warn "No se pudieron cambiar permisos de password_file (normal si no es root)"
        log_success "Archivo de contraseñas creado: $PASSWORD_FILE"
        log_info "  Usuarios: ${MQTT_USER_Z2M}, ${MQTT_USER_HA}"
    else
        log_error "Error al crear el archivo de contraseñas"
        exit 1
    fi
}

# --- Inyectar contraseña Z2M en su configuración ---
patch_z2m_config() {
    local Z2M_CONFIG="${ROOT_DIR}/zigbee2mqtt/data/configuration.yaml"

    if [[ ! -f "$Z2M_CONFIG" ]]; then
        log_warn "Z2M configuration.yaml no encontrado. Se creará en el despliegue."
        return
    fi

    source "$ENV_FILE"

    local patched=false

    if grep -q '__MQTT_USER__' "$Z2M_CONFIG"; then
        sed -i.bak "s|__MQTT_USER__|${MQTT_USER_Z2M}|g" "$Z2M_CONFIG"
        rm -f "${Z2M_CONFIG}.bak"
        patched=true
    fi

    if grep -q '__MQTT_PASS__' "$Z2M_CONFIG"; then
        sed -i.bak "s|__MQTT_PASS__|${MQTT_PASS_Z2M}|g" "$Z2M_CONFIG"
        rm -f "${Z2M_CONFIG}.bak"
        patched=true
    fi

    if [[ "$patched" == "true" ]]; then
        log_success "Credenciales inyectadas en Z2M configuration.yaml"
    else
        log_info "Z2M configuration.yaml ya tiene credenciales configuradas"
    fi
}

# --- Mostrar resumen ---
print_summary() {
    source "$ENV_FILE"
    echo ""
    echo "============================================"
    echo -e "${GREEN}  Credenciales MQTT configuradas${NC}"
    echo "============================================"
    echo ""
    echo "  Zigbee2MQTT:"
    echo "    Usuario:    ${MQTT_USER_Z2M}"
    echo "    Contraseña: ${MQTT_PASS_Z2M:0:8}..."
    echo ""
    echo "  Home Assistant:"
    echo "    Usuario:    ${MQTT_USER_HA}"
    echo "    Contraseña: ${MQTT_PASS_HA:0:8}..."
    echo ""
    echo "  Archivo:      .env"
    if [[ -f "$PASSWORD_FILE" ]]; then
        echo "  Password file: mosquitto/config/password_file"
    fi
    echo ""
    echo "  Próximos pasos:"
    echo "    1. Configurar MQTT en Home Assistant con las credenciales de arriba"
    echo "    2. Ejecutar: bash scripts/deploy.sh"
    echo ""
    echo "============================================"
}

# --- Main ---
main() {
    local force=false
    local apply=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)  force=true; shift ;;
            --apply)  apply=true; shift ;;
            --help|-h)
                echo "Uso: $0 [--apply] [--force]"
                echo ""
                echo "  --apply   Generar + crear password_file de Mosquitto + parchear Z2M"
                echo "  --force   Sobrescribir contraseñas existentes"
                exit 0
                ;;
            *)
                log_error "Argumento desconocido: $1"
                exit 1
                ;;
        esac
    done

    echo ""
    echo "============================================"
    echo "  Generador de secretos - Casa Nórdica"
    echo "============================================"
    echo ""

    ensure_env_file
    generate_mqtt_secrets "$force"

    if [[ "$apply" == "true" ]]; then
        apply_mqtt_passwords
        patch_z2m_config
    fi

    print_summary
}

main "$@"
