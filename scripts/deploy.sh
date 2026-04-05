#!/bin/bash
# ============================================
# DEPLOY.SH - Home Assistant Deployment Script
# ============================================
# Version: 1.0.0
# Last Updated: 2026-03-24
# Description: Complete deployment automation for Casa Nórdica
# Usage: sudo bash ./scripts/deploy.sh
# ============================================

set -euo pipefail

# ============================================
# CONFIGURATION
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${ROOT_DIR}/logs/deploy.log"
ENV_FILE="${ROOT_DIR}/.env"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
BACKUP_DIR="${ROOT_DIR}/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ============================================
# COLORS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# LOGGING FUNCTIONS
# ============================================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# ============================================
# VALIDATION FUNCTIONS
# ============================================
check_prerequisites() {
    log_info "Verifying prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose not installed"
        exit 1
    fi
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found. Copy .env.example to .env"
        exit 1
    fi
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "docker-compose.yml not found"
        exit 1
    fi
    
    log_success "Prerequisites verified"
}

validate_env_file() {
    log_info "Validating .env file..."
    
    source "$ENV_FILE"
    
    local required_vars=(
        "TZ" "PUID" "PGID" "HA_PORT" "Z2M_DEVICE" "MQTT_PASSWORD"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing variables in .env: ${missing_vars[*]}"
        exit 1
    fi
    
    if [[ "$MQTT_PASSWORD" == "CHANGE_ME_GENERATE_NEW_PASSWORD" ]]; then
        log_error "MQTT_PASSWORD not configured. Run generate-secrets.sh"
        exit 1
    fi
    
    log_success ".env file validated"
}

# ============================================
# DIRECTORY SETUP
# ============================================
create_directory_structure() {
    log_info "Creating directory structure..."
    
    local directories=(
        "${ROOT_DIR}/homeassistant/config"
        "${ROOT_DIR}/homeassistant/ssl"
        "${ROOT_DIR}/homeassistant/addons"
        "${ROOT_DIR}/homeassistant/media"
        "${ROOT_DIR}/zigbee2mqtt/data"
        "${ROOT_DIR}/mosquitto/config"
        "${ROOT_DIR}/mosquitto/data"
        "${ROOT_DIR}/mosquitto/log"
        "${ROOT_DIR}/backups/homeassistant"
        "${ROOT_DIR}/backups/zigbee2mqtt"
        "${ROOT_DIR}/backups/mosquitto"
        "${ROOT_DIR}/backups/logs"
        "${ROOT_DIR}/logs"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created: $dir"
        fi
    done
    
    # Permisos: los contenedores gestionan sus propios usuarios internos.
    # Solo asegurar que los directorios son accesibles.
    chmod -R 755 "${ROOT_DIR}/homeassistant" 2>/dev/null || true
    chmod -R 755 "${ROOT_DIR}/zigbee2mqtt" 2>/dev/null || true
    chmod -R 755 "${ROOT_DIR}/mosquitto" 2>/dev/null || true
    chmod -R 755 "${BACKUP_DIR}" 2>/dev/null || true
    
    log_success "Directory structure created"
}

# ============================================
# CONFIGURATION FILES
# ============================================
create_default_configs() {
    log_info "Creating default configurations..."
    
    # Home Assistant configuration.yaml
    if [[ ! -f "${ROOT_DIR}/homeassistant/config/configuration.yaml" ]]; then
        cat > "${ROOT_DIR}/homeassistant/config/configuration.yaml" << 'EOF'
homeassistant:
  name: Casa Nórdica
  unit_system: metric
  temperature_unit: C
  time_zone: Europe/Madrid

default_config:

logger:
  default: warning
  logs:
    homeassistant.components.mqtt: info
    homeassistant.components.androidtv: info

recorder:
  purge_keep_days: 7
  auto_purge: true
  commit_interval: 30
  exclude:
    entities:
      - sensor.*_linkquality
      - sensor.*_rssi
    domains:
      - updater

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.1.0/24
  ip_ban_enabled: true
  login_attempts_threshold: 5

api:
frontend:
automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml

input_boolean:
  modo_cine:
    name: Modo Cine
    icon: mdi:movie
  modo_noche:
    name: Modo Noche
    icon: mdi:weather-night
EOF
        log_info "Created: homeassistant/config/configuration.yaml"
    fi
    
    # Zigbee2MQTT configuration.yaml
    if [[ ! -f "${ROOT_DIR}/zigbee2mqtt/data/configuration.yaml" ]]; then
        cat > "${ROOT_DIR}/zigbee2mqtt/data/configuration.yaml" << EOF
homeassistant: true
permit_join: false

mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://${HOST_IP}:${MQTT_PORT}
  user: homeassistant
  password: ${MQTT_PASSWORD}
  reject_unauthorized: true

serial:
  port: ${Z2M_DEVICE}
  adapter: ${Z2M_ADAPTER}
  baudrate: 460800
  rtscts: true

advanced:
  channel: 25
  pan_id: 0x5A3C
  ext_pan_id: [0x8F, 0x2B, 0x4D, 0x6E, 0x1A, 0x9C, 0x7F, 0x3E]
  network_key: [47, 92, 134, 201, 56, 178, 23, 145, 89, 212, 67, 198, 34, 156, 78, 223]
  log_level: warning
  log_output:
    - console
    - file
  log_rotation: true
  log_max_files: 5
  log_max_size: 5
  transmit_power: 20

frontend:
  port: ${Z2M_PORT}
  host: 0.0.0.0

device_options:
  legacy: false
  retention: 900
EOF
        log_info "Created: zigbee2mqtt/data/configuration.yaml"
    fi
    
    # Mosquitto configuration
    if [[ ! -f "${ROOT_DIR}/mosquitto/config/mosquitto.conf" ]]; then
        cat > "${ROOT_DIR}/mosquitto/config/mosquitto.conf" << EOF
listener ${MQTT_PORT}
listener ${MQTT_WS_PORT}
protocol websockets

allow_anonymous false
password_file /mosquitto/config/password_file

persistence true
persistence_location /mosquitto/data/
persistence_interval 300

log_dest file /mosquitto/log/mosquitto.log
log_type error
log_type warning
log_type notice
log_timestamp true

max_connections 50
max_inflight_messages 20
max_queued_messages 500
EOF
        log_info "Created: mosquitto/config/mosquitto.conf"
    fi
    
    log_success "Default configurations created"
}

# ============================================
# DEVICE VERIFICATION
# ============================================
verify_zigbee_device() {
    log_info "Verifying Zigbee device (${Z2M_DEVICE})..."
    
    if [[ ! -e "${Z2M_DEVICE}" ]]; then
        log_error "Device ${Z2M_DEVICE} not found"
        log_warning "Verify ZBT-2 is connected correctly"
        log_warning "Run: lsusb && ls -l /dev/ttyUSB*"
        exit 1
    fi
    
    if [[ ! -r "${Z2M_DEVICE}" ]]; then
        log_warning "No read permissions on ${Z2M_DEVICE}"
        log_info "Attempting to fix permissions..."
        sudo chmod 666 "${Z2M_DEVICE}" 2>/dev/null || true
    fi
    
    log_success "Zigbee device verified"
}

# ============================================
# BACKUP BEFORE DEPLOY
# ============================================
create_backup_before_deploy() {
    log_info "Creating pre-deployment backup..."
    
    local pre_deploy_backup="${BACKUP_DIR}/pre_deploy_${TIMESTAMP}"
    mkdir -p "$pre_deploy_backup"
    
    if [[ -d "${ROOT_DIR}/homeassistant/config" ]]; then
        tar -czf "${pre_deploy_backup}/homeassistant_config.tar.gz" -C "${ROOT_DIR}/homeassistant" config 2>/dev/null || true
    fi
    
    if [[ -d "${ROOT_DIR}/zigbee2mqtt/data" ]]; then
        tar -czf "${pre_deploy_backup}/zigbee2mqtt_data.tar.gz" -C "${ROOT_DIR}/zigbee2mqtt" data 2>/dev/null || true
    fi
    
    if [[ -d "${ROOT_DIR}/mosquitto/config" ]]; then
        tar -czf "${pre_deploy_backup}/mosquitto_config.tar.gz" -C "${ROOT_DIR}/mosquitto" config 2>/dev/null || true
    fi
    
    log_success "Pre-deployment backup created: ${pre_deploy_backup}"
}

# ============================================
# CONTAINER MANAGEMENT
# ============================================
stop_existing_containers() {
    log_info "Stopping existing containers..."
    
    cd "$ROOT_DIR"
    
    if docker-compose ps -q 2>/dev/null | grep -q .; then
        docker-compose down --remove-orphans
        log_info "Containers stopped"
        sleep 5
    else
        log_info "No containers running"
    fi
}

deploy_containers() {
    log_info "Deploying containers..."
    
    cd "$ROOT_DIR"
    
    # Validate docker-compose.yml
    docker-compose config --quiet || {
        log_error "Invalid docker-compose.yml"
        exit 1
    }
    
    # Pull images
    log_info "Pulling images..."
    docker-compose pull
    
    # Deploy
    log_info "Starting containers..."
    docker-compose up -d --force-recreate --remove-orphans
    
    # Wait for services to be healthy
    log_info "Waiting for services to become healthy..."
    sleep 30
    
    # Verify status
    docker-compose ps
    
    log_success "Containers deployed"
}

# ============================================
# VERIFICATION
# ============================================
verify_deployment() {
    log_info "Verifying deployment..."
    
    local services=("home-assistant" "zigbee2mqtt" "mosquitto")
    local all_healthy=true
    
    for service in "${services[@]}"; do
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "unknown")
        
        if [[ "$health" == "healthy" ]]; then
            log_success "$service: healthy"
        elif [[ "$health" == "starting" ]]; then
            log_warning "$service: starting (waiting...)"
        else
            log_error "$service: $health"
            all_healthy=false
        fi
    done
    
    if [[ "$all_healthy" == "false" ]]; then
        log_warning "Some services not healthy. Check logs."
        log_info "docker-compose logs -f"
    else
        log_success "All services healthy"
    fi
}

# ============================================
# SUMMARY
# ============================================
print_summary() {
    echo ""
    echo "============================================"
    log_success "DEPLOYMENT COMPLETED"
    echo "============================================"
    echo ""
    echo "📍 Services available:"
    echo "   • Home Assistant: http://${HOST_IP}:${HA_PORT}"
    echo "   • Zigbee2MQTT:    http://${HOST_IP}:${Z2M_PORT}"
    echo "   • MQTT Broker:    ${HOST_IP}:${MQTT_PORT}"
    echo ""
    echo "📋 Useful commands:"
    echo "   • View logs:       docker-compose logs -f"
    echo "   • View status:     docker-compose ps"
    echo "   • Stop:            docker-compose down"
    echo "   • Restart:         docker-compose restart"
    echo "   • Backup:          ./scripts/backup.sh"
    echo "   • Rollback:        ./scripts/rollback.sh"
    echo ""
    echo "🔐 Security:"
    echo "   • Change default passwords"
    echo "   • Enable 2FA in Home Assistant"
    echo "   • Configure Synology firewall"
    echo ""
    echo "============================================"
}

# ============================================
# MAIN
# ============================================
main() {
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "============================================"
    echo "🚀 CASA NÓRDICA DEPLOYMENT"
    echo "============================================"
    echo "Timestamp: ${TIMESTAMP}"
    echo "Root Dir:  ${ROOT_DIR}"
    echo "============================================"
    echo ""
    
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_info "Starting deployment..."
    
    check_prerequisites
    validate_env_file
    create_directory_structure
    create_default_configs
    verify_zigbee_device
    create_backup_before_deploy
    stop_existing_containers
    deploy_containers
    verify_deployment
    print_summary
    
    log_success "Deployment completed successfully"
}

main "$@"