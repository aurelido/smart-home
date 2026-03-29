#!/bin/bash
# ============================================
# CLEANUP.SH - Stop and Cleanup Environment
# ============================================
# Version: 1.0.0
# Last Updated: 2026-03-24
# Description: Stop services and clean up resources
# Usage: ./scripts/cleanup.sh --level=soft|medium|hard
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${ROOT_DIR}/logs/cleanup.log"
ENV_FILE="${ROOT_DIR}/.env"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
BACKUP_DIR="${ROOT_DIR}/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLEANUP_LEVEL="soft"
FORCE=false
CREATE_BACKUP=true

log() {
    local level="$1"
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

create_backup() {
    if [[ "$CREATE_BACKUP" == "false" ]]; then
        log_info "Backup skipped (--backup not specified)"
        return 0
    fi
    
    log_info "Creating pre-cleanup backup..."
    
    local backup_path="${BACKUP_DIR}/pre_cleanup_${TIMESTAMP}"
    mkdir -p "$backup_path"
    
    if [[ -d "${ROOT_DIR}/homeassistant/config" ]]; then
        tar -czf "${backup_path}/homeassistant_config.tar.gz" -C "${ROOT_DIR}/homeassistant" config 2>/dev/null && \
        log_success "Home Assistant config backed up" || \
        log_warning "Home Assistant config backup failed"
    fi
    
    if [[ -d "${ROOT_DIR}/zigbee2mqtt/data" ]]; then
        tar -czf "${backup_path}/zigbee2mqtt_data.tar.gz" -C "${ROOT_DIR}/zigbee2mqtt" data 2>/dev/null && \
        log_success "Zigbee2MQTT data backed up" || \
        log_warning "Zigbee2MQTT data backup failed"
    fi
    
    if [[ -d "${ROOT_DIR}/mosquitto/config" ]]; then
        tar -czf "${backup_path}/mosquitto_config.tar.gz" -C "${ROOT_DIR}/mosquitto" config 2>/dev/null && \
        log_success "Mosquitto config backed up" || \
        log_warning "Mosquitto config backup failed"
    fi
    
    log_success "Backup completed: ${backup_path}"
}

stop_containers() {
    log_info "Stopping containers..."
    
    cd "$ROOT_DIR"
    
    local running=$(docker-compose ps -q 2>/dev/null | wc -l)
    
    if [[ $running -eq 0 ]]; then
        log_info "No containers running"
        return 0
    fi
    
    docker-compose stop --timeout 30
    
    log_success "Containers stopped"
}

remove_containers() {
    if [[ "$CLEANUP_LEVEL" == "soft" ]]; then
        log_info "Soft level: Containers not removed"
        return 0
    fi
    
    log_info "Removing containers..."
    
    cd "$ROOT_DIR"
    docker-compose rm -f
    
    log_success "Containers removed"
}

remove_images() {
    if [[ "$CLEANUP_LEVEL" != "hard" ]]; then
        log_info "${CLEANUP_LEVEL} level: Images not removed"
        return 0
    fi
    
    log_warning "⚠️  Removing Docker images (will require download on next deploy)..."
    
    if [[ "$FORCE" != "true" ]]; then
        read -p "Remove images? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Image removal cancelled"
            return 0
        fi
    fi
    
    cd "$ROOT_DIR"
    docker rmi ${HA_IMAGE}:${HA_TAG} 2>/dev/null || true
    docker rmi ${Z2M_IMAGE}:${Z2M_TAG} 2>/dev/null || true
    docker rmi ${MQTT_IMAGE}:${MQTT_TAG} 2>/dev/null || true
    docker image prune -f
    
    log_success "Images removed"
}

remove_volumes() {
    if [[ "$CLEANUP_LEVEL" != "hard" ]]; then
        log_info "${CLEANUP_LEVEL} level: Volumes not removed"
        return 0
    fi
    
    log_warning "⚠️  REMOVING VOLUMES (persistent data will be lost)..."
    
    if [[ "$FORCE" != "true" ]]; then
        read -p "ARE YOU SURE? Type 'DELETE' to confirm: " confirm
        if [[ "$confirm" != "DELETE" ]]; then
            log_info "Volume removal cancelled"
            return 0
        fi
    fi
    
    cd "$ROOT_DIR"
    docker-compose down -v 2>/dev/null || true
    docker volume prune -f
    
    log_success "Volumes removed"
}

cleanup_docker_artifacts() {
    log_info "Cleaning Docker artifacts..."
    
    docker container prune -f
    
    if [[ "$CLEANUP_LEVEL" == "hard" ]]; then
        docker image prune -a -f
    else
        docker image prune -f
    fi
    
    docker volume prune -f
    docker builder prune -f
    
    log_success "Docker artifacts cleaned"
}

verify_cleanup() {
    log_info "Verifying cleanup..."
    
    cd "$ROOT_DIR"
    
    local running=$(docker-compose ps -q 2>/dev/null | wc -l)
    log_info "Containers running: ${running}"
    
    local disk_usage=$(df -h "${ROOT_DIR}" | tail -1 | awk '{print $5}')
    log_info "Disk usage: ${disk_usage}"
    
    log_success "Verification completed"
}

print_summary() {
    echo ""
    echo "============================================"
    log_success "CLEANUP COMPLETED"
    echo "============================================"
    echo ""
    echo "📊 Summary:"
    echo "   • Cleanup level: ${CLEANUP_LEVEL}"
    echo "   • Backup created: ${CREATE_BACKUP}"
    echo ""
    echo "📍 Backup location: ${BACKUP_DIR}/pre_cleanup_${TIMESTAMP}"
    echo ""
    echo "🚀 To redeploy:"
    echo "   ./scripts/deploy.sh"
    echo ""
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --level=*)
                CLEANUP_LEVEL="${1#*=}"
                if [[ ! "$CLEANUP_LEVEL" =~ ^(soft|medium|hard)$ ]]; then
                    log_error "Invalid level: ${CLEANUP_LEVEL}. Use: soft, medium, hard"
                    exit 1
                fi
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --no-backup)
                CREATE_BACKUP=false
                shift
                ;;
            --help|-h)
                echo "Usage: ./scripts/cleanup.sh [--level=soft|medium|hard] [--force] [--no-backup]"
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

confirm_cleanup() {
    if [[ "$FORCE" == "true" ]]; then
        log_warning "⚠️  FORCE mode: No confirmations"
        return 0
    fi
    
    echo ""
    log_warning "⚠️  CLEANUP WARNING"
    echo ""
    echo "Selected level: ${CLEANUP_LEVEL}"
    echo ""
    
    case $CLEANUP_LEVEL in
        soft)
            echo "✅ Actions:"
            echo "   • Stop containers"
            echo ""
            echo "✅ Reversible: YES (docker-compose start)"
            ;;
        medium)
            echo "✅ Actions:"
            echo "   • Stop containers"
            echo "   • Remove containers"
            echo ""
            echo "✅ Reversible: YES (redeploy)"
            ;;
        hard)
            echo "❌ Actions:"
            echo "   • Stop containers"
            echo "   • Remove containers"
            echo "   • Remove images"
            echo "   • Remove volumes (DATA LOSS)"
            echo ""
            echo "❌ Reversible: NO (need backup restore)"
            ;;
    esac
    
    echo ""
    read -p "Continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

main() {
    parse_args "$@"
    
    echo ""
    echo "============================================"
    echo "🧹 CASA NÓRDICA CLEANUP"
    echo "============================================"
    echo "Timestamp: ${TIMESTAMP}"
    echo "Level:     ${CLEANUP_LEVEL}"
    echo "============================================"
    echo ""
    
    mkdir -p "$(dirname "$LOG_FILE")"
    
    create_backup
    confirm_cleanup
    stop_containers
    remove_containers
    remove_images
    remove_volumes
    cleanup_docker_artifacts
    verify_cleanup
    print_summary
}

main "$@"