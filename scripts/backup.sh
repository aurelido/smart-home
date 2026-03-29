#!/bin/bash
# ============================================
# BACKUP.SH - Backup Automation Script
# ============================================
# Version: 1.0.0
# Last Updated: 2026-03-24
# Description: Automated backup for all services
# Usage: ./scripts/backup.sh [--encrypt]
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${ROOT_DIR}/logs/backup.log"
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

backup_homeassistant() {
    log_info "Backing up Home Assistant..."
    
    local backup_file="${BACKUP_DIR}/homeassistant/homeassistant_backup_${TIMESTAMP}.tar.gz"
    mkdir -p "$(dirname "$backup_file")"
    
    tar -czf "$backup_file" -C "${ROOT_DIR}/homeassistant" config 2>/dev/null
    
    if [[ -f "$backup_file" ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_success "Home Assistant backup: ${backup_file} (${size})"
    else
        log_error "Failed to create Home Assistant backup"
        return 1
    fi
}

backup_zigbee2mqtt() {
    log_info "Backing up Zigbee2MQTT..."
    
    local backup_file="${BACKUP_DIR}/zigbee2mqtt/zigbee2mqtt_backup_${TIMESTAMP}.tar.gz"
    mkdir -p "$(dirname "$backup_file")"
    
    tar -czf "$backup_file" -C "${ROOT_DIR}/zigbee2mqtt" data 2>/dev/null
    
    if [[ -f "$backup_file" ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_success "Zigbee2MQTT backup: ${backup_file} (${size})"
    fi
}

backup_mosquitto() {
    log_info "Backing up Mosquitto..."
    
    local backup_file="${BACKUP_DIR}/mosquitto/mosquitto_backup_${TIMESTAMP}.tar.gz"
    mkdir -p "$(dirname "$backup_file")"
    
    tar -czf "$backup_file" -C "${ROOT_DIR}/mosquitto" config data 2>/dev/null
    
    if [[ -f "$backup_file" ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_success "Mosquitto backup: ${backup_file} (${size})"
    fi
}

cleanup_old_backups() {
    log_info "Cleaning old backups (>${BACKUP_RETENTION_DAYS} days)..."
    
    find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
    
    local remaining=$(find "${BACKUP_DIR}" -name "*.tar.gz" | wc -l)
    log_info "Remaining backups: ${remaining}"
}

encrypt_backup() {
    local backup_file="$1"
    local encrypted_file="${backup_file}.enc"
    
    log_info "Encrypting backup: ${backup_file}"
    
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "$backup_file" \
        -out "$encrypted_file" \
        -pass pass:"${HA_BACKUP_PASSWORD}"
    
    rm "$backup_file"
    
    log_success "Backup encrypted: ${encrypted_file}"
}

main() {
    local encrypt=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --encrypt)
                encrypt=true
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
    echo "💾 CASA NÓRDICA BACKUP"
    echo "============================================"
    echo "Timestamp: ${TIMESTAMP}"
    echo "============================================"
    echo ""
    
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "${BACKUP_DIR}/homeassistant"
    mkdir -p "${BACKUP_DIR}/zigbee2mqtt"
    mkdir -p "${BACKUP_DIR}/mosquitto"
    
    log_info "Starting backup..."
    
    backup_homeassistant
    backup_zigbee2mqtt
    backup_mosquitto
    
    if [[ "$encrypt" == "true" ]] && [[ -n "${HA_BACKUP_PASSWORD:-}" ]]; then
        log_info "Encrypting backups..."
        find "${BACKUP_DIR}" -name "*.tar.gz" ! -name "*.enc" -exec openssl enc -aes-256-cbc -salt -pbkdf2 -in {} -out {}.enc -pass pass:"${HA_BACKUP_PASSWORD}" \;
        find "${BACKUP_DIR}" -name "*.tar.gz" ! -name "*.enc" -delete
    fi
    
    cleanup_old_backups
    
    echo ""
    echo "============================================"
    log_success "BACKUP COMPLETED"
    echo "============================================"
    echo ""
    echo "Backups location: ${BACKUP_DIR}"
    echo "Retention: ${BACKUP_RETENTION_DAYS} days"
    echo ""
}

main "$@"