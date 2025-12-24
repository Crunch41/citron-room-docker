#!/bin/bash
set -e

# Default values
ROOM_NAME="${ROOM_NAME:-Citron Room}"
ROOM_DESCRIPTION="${ROOM_DESCRIPTION:-}"
PORT="${PORT:-24872}"
MAX_MEMBERS="${MAX_MEMBERS:-16}"
BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0}"
PASSWORD="${PASSWORD:-}"
PREFERRED_GAME="${PREFERRED_GAME:-Any Game}"
PREFERRED_GAME_ID="${PREFERRED_GAME_ID:-0}"
BAN_LIST_FILE="${BAN_LIST_FILE:-/home/citron/.local/share/citron-room/ban_list.txt}"
LOG_DIR="${LOG_DIR:-/home/citron/.local/share/citron-room}"
ENABLE_CITRON_MODS="${ENABLE_CITRON_MODS:-false}"

# Log settings
MAX_LOG_FILES="${MAX_LOG_FILES:-10}"  # Keep last 10 session logs

# Generate timestamped log filename for this session
SESSION_TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="${LOG_DIR}/citron-room_${SESSION_TIMESTAMP}.log"
LATEST_LOG="${LOG_DIR}/citron-room.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Create symlink for "latest" log
ln -sf "$LOG_FILE" "$LATEST_LOG"

# Symlink Citron's internal log path to our current session log
# (Citron writes to ~/.local/share/citron/log/citron_log.txt internally)
CITRON_LOG_DIR="/home/citron/.local/share/citron/log"
mkdir -p "$CITRON_LOG_DIR"
ln -sf "$LOG_FILE" "${CITRON_LOG_DIR}/citron_log.txt"

# Function: Cleanup old session logs (keep last N)
cleanup_old_logs() {
    local log_count=$(ls -1 "${LOG_DIR}"/citron-room_*.log 2>/dev/null | wc -l)
    if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
        local to_delete=$((log_count - MAX_LOG_FILES))
        ls -1t "${LOG_DIR}"/citron-room_*.log | tail -n "$to_delete" | while read -r old_log; do
            echo "Removing old session log: $(basename "$old_log")"
            rm -f "$old_log"
        done
    fi
}

# Cleanup old logs before starting
cleanup_old_logs

# Determine mode
MODE="Private (not announcing)"
if [ -n "$USERNAME" ] && [ -n "$TOKEN" ] && [ -n "$WEB_API_URL" ]; then
    MODE="Public (announcing to web service every 15s)"
fi

# Print session header
{
    echo "================================================================================"
    echo "Citron Room Server - Session Started"
    echo "================================================================================"
    echo "Timestamp: $(date -Iseconds)"
    echo "Log File:  $(basename "$LOG_FILE")"
    echo ""
    echo "Configuration:"
    echo "  Room Name: $ROOM_NAME"
    if [ -n "$ROOM_DESCRIPTION" ]; then
        echo "  Description: $ROOM_DESCRIPTION"
    fi
    echo "  Port: $PORT"
    echo "  Max Members: $MAX_MEMBERS (max: 254)"
    echo "  Bind Address: $BIND_ADDRESS"
    echo "  Ban List: $BAN_LIST_FILE"
    echo "  Network Version: 1"
    echo "  Mode: $MODE"
    echo "================================================================================"
    echo ""
} | tee "$LOG_FILE"

# Build command
CMD=("/usr/local/bin/citron-room" \
  "--room-name" "$ROOM_NAME" \
  "--port" "$PORT" \
  "--max_members" "$MAX_MEMBERS" \
  "--bind-address" "$BIND_ADDRESS" \
  "--preferred-game" "$PREFERRED_GAME" \
  "--preferred-game-id" "$PREFERRED_GAME_ID" \
  "--ban-list-file" "$BAN_LIST_FILE")

# Note: --log-file is NOT passed because Citron ignores it
# Instead, we symlink Citron's internal log path to our session log

# Add optional parameters
if [ -n "$ROOM_DESCRIPTION" ]; then
    CMD+=("--room-description" "$ROOM_DESCRIPTION")
fi

if [ -n "$PASSWORD" ]; then
    CMD+=("--password" "$PASSWORD")
fi

if [ "$ENABLE_CITRON_MODS" = "true" ]; then
    CMD+=("--enable-citron-mods")
fi

# Add public room credentials
if [ -n "$USERNAME" ] && [ -n "$TOKEN" ] && [ -n "$WEB_API_URL" ]; then
    CMD+=("--username" "$USERNAME" \
          "--token" "$TOKEN" \
          "--web-api-url" "$WEB_API_URL")
fi

# Execute with ANSI stripping for log file (keep colors in console)
exec "${CMD[@]}" 2>&1 | tee >(sed -u 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")
