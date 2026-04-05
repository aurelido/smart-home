#!/bin/bash
# ============================================
# ROLLBACK.SH - Recovery from Backup
# ============================================
# Version: 1.0.0
# Last Updated: 2026-03-24
# Description: Restore system from previous backup
# Usage: ./scripts/rollback.sh --backup=YYYYMMDD_HHMMSS
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${ROOT_DIR}/logs/rollback.log"
BACKUP_DIR="${ROOT_DIR}/backup"
ENV_FILE="${ROOT_DIR}/.env"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

list_available_backups() {
    log_info "Available backups:"
    echo ""
    
    if [[ ! -d "${BACKUP_DIR}/homeassistant" ]]; then
        log_error "No backups available"
        return 1
    fi
    
    ls -lht "${BACKUP_DIR}/homeassistant/"*.tar.gz 2>/dev/null | head -10 || {
        log_warning "No Home Assistant backups found"
    }
}

create_current_backup() {
    log_info "Creating backup of current state before rollback..."
    
    local current_backup="${BACKUP_DIR}/pre_rollback_${TIMESTAMP}"
    mkdir -p "$current_backup"
    
    tar -czf "${current_backup}/homeassistant_config.tar.gz" -C "${ROOT_DIR}/homeassistant" config 2>/dev/null || true
    tar -czf "${current_backup}/zigbee2mqtt_data.tar.gz" -C "${ROOT_DIR}/zigbee2mqtt" data 2>/dev/null || true
    tar -czf "${current_backup}/mosquitto_config.tar.gz" -C "${ROOT_DIR}/mosquitto" config 2>/dev/null || true
    
    log_success "Pre-rollback backup created: ${current_backup}"
}

stop_services() {
    log_info "Stopping services..."
    
    cd "$ROOT_DIR"
    docker-compose down
    sleep 5
    
    log_success "Services stopped"
}

restore_homeassistant() {
    local backup_file="$1"
    
    log_info "Restoring Home Assistant configuration..."
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup not found: $backup_file"
        return 1
    fi
    
    tar -xzf "$backup_file" -C "${ROOT_DIR}/homeassistant"
    chown -R ${PUID}:${PGID} "${ROOT_DIR}/homeassistant/config"
    
    log_success "Home Assistant restored"
}

restore_zigbee2mqtt() {
    local backup_file="$1"
    
    log_info "Restoring Zigbee2MQTT data..."
    
    if [[ ! -f "$backup_file" ]]; then
        log_warning "Zigbee2MQTT backup not found, skipping..."
        return 0
    fi
    
    tar -xzf "$backup_file" -C "${ROOT_DIR}/zigbee2mqtt"
    chown -R ${PUID}:${PGID} "${ROOT_DIR}/zigbee2mqtt/data"
    
    log_success "Zigbee2MQTT restored"
}

restore_mosquitto() {
    local backup_file="$1"
    
    log_info "Restoring Mosquitto configuration..."
    
    if [[ ! -f "$backup_file" ]]; then
        log_warning "Mosquitto backup not found, skipping..."
        return 0
    fi
    
    tar -xzf "$backup_file" -C "${ROOT_DIR}/mosquitto"
    chown -R ${PUID}:${PGID} "${ROOT_DIR}/mosquitto/config"
    
    log_success "Mosquitto restored"
}

start_services() {
    log_info "Starting services..."
    
    cd "$ROOT_DIR"
    docker-compose up -d
    
    log_info "Waiting 30 seconds for services to start..."
    sleep 30
    
    docker-compose ps
    
    log_success "Services started"
}

verify_rollback() {
    log_info "Verifying rollback..."
    
    local running=$(docker-compose ps -q | wc -l)
    
    if [[ $running -eq 3 ]]; then
        log_success "Rollback verified: 3 services running"
    else
        log_error "Rollback incomplete: ${running}/3 services running"
        return 1
    fi
}

main() {
    local backup_date=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup=*)
                backup_date="${1#*=}"
                shift
                ;;
            --list)
                list_available_backups
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "============================================"
    echo "🔄 CASA NÓRDICA ROLLBACK"
    echo "============================================"
    echo ""
    
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_warning "⚠️  THIS WILL RESTORE A PREVIOUS VERSION"
    log_warning "⚠️  Recent changes will be lost"
    echo ""
    read -p "Continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi
    
    if [[ -z "$backup_date" ]]; then
        list_available_backups
        read -p "Enter backup date (YYYYMMDD_HHMMSS): " backup_date
    fi
    
    local ha_backup="${BACKUP_DIR}/homeassistant/homeassistant_backup_${backup_date}.tar.gz"
    local z2m_backup="${BACKUP_DIR}/zigbee2mqtt/zigbee2mqtt_backup_${backup_date}.tar.gz"
    local mqtt_backup="${BACKUP_DIR}/mosquitto/mosquitto_backup_${backup_date}.tar.gz"
    
    if [[ ! -f "$ha_backup" ]]; then
        log_error "Home Assistant backup not found: $ha_backup"
        exit 1
    fi
    
    create_current_backup
    stop_services
    restore_homeassistant "$ha_backup"
    restore_zigbee2mqtt "$z2m_backup"
    restore_mosquitto "$mqtt_backup"
    start_services
    verify_rollback
    
    echo ""
    echo "============================================"
    log_success "ROLLBACK COMPLETED"
    echo "============================================"
    echo ""
    echo "Backup restored: ${backup_date}"
    echo "Safety backup: pre_rollback_${TIMESTAMP}"
    echo ""
}

main "$@"