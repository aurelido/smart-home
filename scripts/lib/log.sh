#!/bin/bash
# =============================================================================
# Smart Home - Librería de logging centralizada
# =============================================================================
# Uso en scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
#   log_init "nombre_script"
#
# Niveles: DEBUG, INFO, WARN, ERROR
# Salida dual: consola (con colores) + archivo (texto plano)
#
# Variables de entorno opcionales:
#   LOG_LEVEL=DEBUG|INFO|WARN|ERROR  (por defecto: INFO)
#   LOG_DIR=<ruta>                   (por defecto: $PROJECT_DIR/logs)
#   LOG_MAX_FILES=<n>                (por defecto: 30)
# =============================================================================

# Evitar carga múltiple
[[ -n "${_LOG_LIB_LOADED:-}" ]] && return 0
_LOG_LIB_LOADED=1

# --- Configuración ---
_LOG_LEVEL="${LOG_LEVEL:-INFO}"
_LOG_MAX_FILES="${LOG_MAX_FILES:-30}"
_LOG_SCRIPT_NAME=""
_LOG_FILE=""
_LOG_START_TIME=""
_LOG_STEP_COUNT=0

# --- Niveles numéricos ---
_log_level_num() {
    case "${1^^}" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# --- Colores (solo si hay terminal) ---
if [ -t 1 ]; then
    _C_RESET='\033[0m'
    _C_GRAY='\033[0;90m'
    _C_GREEN='\033[0;32m'
    _C_YELLOW='\033[1;33m'
    _C_RED='\033[0;31m'
    _C_CYAN='\033[0;36m'
    _C_BOLD='\033[1m'
else
    _C_RESET='' _C_GRAY='' _C_GREEN='' _C_YELLOW=''
    _C_RED='' _C_CYAN='' _C_BOLD=''
fi

# --- Mapeo nivel → color ---
_log_color() {
    case "$1" in
        DEBUG) echo "$_C_GRAY"   ;;
        INFO)  echo "$_C_GREEN"  ;;
        WARN)  echo "$_C_YELLOW" ;;
        ERROR) echo "$_C_RED"    ;;
        *)     echo "$_C_RESET"  ;;
    esac
}

# =============================================================================
# Función principal de logging (uso interno)
# =============================================================================
_log_write() {
    local level="$1"
    shift
    local message="$*"

    # Filtrar por nivel configurado
    local current_num; current_num=$(_log_level_num "$_LOG_LEVEL")
    local msg_num;     msg_num=$(_log_level_num "$level")
    [[ "$msg_num" -lt "$current_num" ]] && return 0

    local timestamp; timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local level_padded; level_padded=$(printf '%-5s' "$level")

    # Formato consola (con colores)
    local color; color=$(_log_color "$level")
    echo -e "${_C_GRAY}${timestamp}${_C_RESET} ${color}${level_padded}${_C_RESET} ${_C_CYAN}[${_LOG_SCRIPT_NAME}]${_C_RESET} ${message}"

    # Formato archivo (sin colores)
    if [[ -n "$_LOG_FILE" ]]; then
        echo "${timestamp} ${level_padded} [${_LOG_SCRIPT_NAME}] ${message}" >> "$_LOG_FILE" 2>/dev/null || true
    fi

    # Errores también van a stderr
    if [[ "$level" == "ERROR" ]]; then
        echo -e "${_C_RED}${timestamp} ${level_padded} [${_LOG_SCRIPT_NAME}] ${message}${_C_RESET}" >&2
    fi
}

# =============================================================================
# Funciones públicas de logging
# =============================================================================
log_debug() { _log_write "DEBUG" "$@"; }
log_info()  { _log_write "INFO"  "$@"; }
log_warn()  { _log_write "WARN"  "$@"; }
log_error() { _log_write "ERROR" "$@"; }

# --- Paso numerado (para seguimiento de progreso) ---
log_step() {
    _LOG_STEP_COUNT=$((_LOG_STEP_COUNT + 1))
    _log_write "INFO" "${_C_BOLD}[Paso ${_LOG_STEP_COUNT}]${_C_RESET} $*"
}

# --- Separador visual ---
log_separator() {
    local label="${1:-}"
    if [[ -n "$label" ]]; then
        _log_write "INFO" "━━━ ${label} ━━━"
    else
        _log_write "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# --- Ejecutar comando con logging ---
log_exec() {
    local cmd_display="$*"
    log_debug "Ejecutando: ${cmd_display}"

    local output
    local exit_code=0
    output=$("$@" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        [[ -n "$output" ]] && log_debug "$output"
    else
        log_error "Comando falló (exit=$exit_code): ${cmd_display}"
        [[ -n "$output" ]] && log_error "$output"
    fi

    return $exit_code
}

# =============================================================================
# Inicialización y ciclo de vida
# =============================================================================

# --- Inicializar logging ---
# Uso: log_init "deploy" [log_dir]
log_init() {
    _LOG_SCRIPT_NAME="${1:?log_init requiere nombre de script}"
    local log_dir="${2:-${LOG_DIR:-}}"

    # Auto-detectar PROJECT_DIR y LOG_DIR
    if [[ -z "$log_dir" ]]; then
        local script_dir; script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
        local project_dir; project_dir="$(dirname "$script_dir")"
        log_dir="$project_dir/logs"
    fi

    mkdir -p "$log_dir"

    # Archivo de log diario por script
    _LOG_FILE="${log_dir}/${_LOG_SCRIPT_NAME}_$(date '+%Y%m%d').log"
    _LOG_START_TIME=$(date +%s)
    _LOG_STEP_COUNT=0

    # Rotación al iniciar
    _log_rotate "$log_dir"

    # Trap para capturar errores y medir duración
    trap '_log_on_exit $?' EXIT
    trap '_log_on_error $LINENO' ERR

    log_separator "${_LOG_SCRIPT_NAME^^} — Inicio"
    log_debug "Nivel de log: ${_LOG_LEVEL}"
    log_debug "Archivo de log: ${_LOG_FILE}"
    log_debug "PID: $$ | Usuario: $(whoami)"
}

# --- Rotación de logs ---
_log_rotate() {
    local log_dir="$1"
    local count
    count=$(find "$log_dir" -name "*.log" -type f 2>/dev/null | wc -l)

    if [[ "$count" -gt "$_LOG_MAX_FILES" ]]; then
        local to_delete=$((count - _LOG_MAX_FILES))
        find "$log_dir" -name "*.log" -type f -printf '%T+ %p\n' 2>/dev/null \
            | sort | head -n "$to_delete" | cut -d' ' -f2- \
            | xargs rm -f 2>/dev/null || true
        log_debug "Rotación: eliminados $to_delete logs antiguos"
    fi
}

# --- Trap: al salir ---
_log_on_exit() {
    local exit_code=$1
    local end_time; end_time=$(date +%s)
    local duration=$((end_time - _LOG_START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    if [[ $exit_code -eq 0 ]]; then
        log_separator "${_LOG_SCRIPT_NAME^^} — Fin (${minutes}m ${seconds}s)"
    else
        log_error "Finalizado con error (código: $exit_code) tras ${minutes}m ${seconds}s"
        log_separator "${_LOG_SCRIPT_NAME^^} — Fin con ERRORES"
    fi
}

# --- Trap: en error ---
_log_on_error() {
    local line=$1
    log_error "Error en línea $line del script ${_LOG_SCRIPT_NAME}"
}

# =============================================================================
# Utilidades
# =============================================================================

# --- Obtener ruta del log actual ---
log_file_path() {
    echo "$_LOG_FILE"
}

# --- Mostrar últimas N líneas del log ---
log_tail() {
    local lines="${1:-20}"
    if [[ -f "$_LOG_FILE" ]]; then
        tail -n "$lines" "$_LOG_FILE"
    fi
}
