#!/bin/bash
# ============================================
# MAINTENANCE.SH - Routine Maintenance
# ============================================
# Version: 1.0.0
# Last Updated: 2026-03-24
# Description: Weekly maintenance tasks
# Usage: ./scripts/maintenance.sh [--clean] [--update] [--health]
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${ROOT_DIR}/logs/maintenance.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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

clean_docker() {
    log_info "Cleaning Docker resources..."
    
    docker container prune -f
    log_success "Stopped containers removed"
    
    docker image prune -f
    log_success "Unused images removed"
    
    docker volume prune -f
    log_success "Unused volumes removed"
    
    docker builder prune -f
    log_success "Build cache removed"
}

update_images() {
    log_info "Updating Docker images..."
    
    cd "$ROOT_DIR"
    docker-compose pull
    
    log_success "Images updated"
    log_warning "Restart services to apply: docker-compose up -d --force-recreate"
}

check_health() {
    log_info "Checking service health..."
    
    local services=("home-assistant" "zigbee2mqtt" "mosquitto")
    
    for service in "${services[@]}"; do
        local status=$(docker inspect --format='{{.State.Status}}' "$service" 2>/dev/null || echo "not found")
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "no healthcheck")
        
        if [[ "$status" == "running" ]]; then
            log_success "$service: running ($health)"
        else
            log_error "$service: $status"
        fi
    done
}

check_disk_usage() {
    log_info "Checking disk usage..."
    
    local usage=$(df -h "${ROOT_DIR}" | tail -1 | awk '{print $5}' | tr -d '%')
    
    if [[ $usage -gt 85 ]]; then
        log_warning "High disk usage: ${usage}%"
    elif [[ $usage -gt 95 ]]; then
        log_error "Critical disk usage: ${usage}%"
    else
        log_success "Disk usage: ${usage}%"
    fi
}

restart_services() {
    log_info "Restarting services..."
    
    cd "$ROOT_DIR"
    docker-compose restart
    
    log_success "Services restarted"
}

main() {
    echo ""
    echo "============================================"
    echo "🔧 CASA NÓRDICA MAINTENANCE"
    echo "============================================"
    echo ""
    
    mkdir -p "$(dirname "$LOG_FILE")"
    
    check_health
    check_disk_usage
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                clean_docker
                shift
                ;;
            --update)
                update_images
                shift
                ;;
            --restart)
                restart_services
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
    
    echo ""
    log_success "Maintenance completed"
    echo ""
}

main "$@"