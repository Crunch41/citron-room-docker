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
LOG_FILE="${LOG_FILE:-/home/citron/.local/share/citron-room/citron-room.log}"
ENABLE_CITRON_MODS="${ENABLE_CITRON_MODS:-false}"

# Log rotation settings
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB
MAX_LOG_FILES=7

# Function: Rotate logs if needed
rotate_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi
    
    local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    
    if [ "$log_size" -gt "$MAX_LOG_SIZE" ]; then
        echo "Rotating log file (size: $((log_size / 1024 / 1024))MB)"
        
        # Rotate existing backup logs
        for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
            if [ -f "${LOG_FILE}.$i.gz" ]; then
                mv "${LOG_FILE}.$i.gz" "${LOG_FILE}.$((i + 1)).gz"
            fi
        done
        
        # Compress and rotate current log
        gzip -c "$LOG_FILE" > "${LOG_FILE}.1.gz"
        > "$LOG_FILE"  # Truncate current log
        
        # Delete old logs beyond retention
        if [ -f "${LOG_FILE}.$((MAX_LOG_FILES + 1)).gz" ]; then
            rm -f "${LOG_FILE}.$((MAX_LOG_FILES + 1)).gz"
        fi
        
        echo "Log rotated. Keeping last $MAX_LOG_FILES rotations."
    fi
}

# Determine mode
MODE="Private (not announcing)"
if [ -n "$USERNAME" ] && [ -n "$TOKEN" ] && [ -n "$WEB_API_URL" ]; then
    MODE="Public (announcing to web service every 15s)"
fi

# Rotate logs before starting
rotate_logs

# Print configuration header (with ISO timestamp)
{
    echo "================================================================================"
    echo "Citron Room Server Started: $(date -Iseconds)"
    echo "================================================================================"
    echo "Configuration:"
    echo "  Room Name: $ROOM_NAME"
    if [ -n "$ROOM_DESCRIPTION" ]; then
        echo "  Description: $ROOM_DESCRIPTION"
    fi
    echo "  Port: $PORT"
    echo "  Max Members: $MAX_MEMBERS (max: 254)"
    echo "  Bind Address: $BIND_ADDRESS"
    echo "  Ban List: $BAN_LIST_FILE"
    echo "  Log File: $LOG_FILE (rotate at $((MAX_LOG_SIZE / 1024 / 1024))MB, keep ${MAX_LOG_FILES} files)"
    echo "  Network Version: 1"
    echo "  Mode: $MODE"
    echo "================================================================================"
    echo ""
} | tee -a "$LOG_FILE"

# Build command
CMD=("/usr/local/bin/citron-room" \
  "--room-name" "$ROOM_NAME" \
  "--port" "$PORT" \
  "--max_members" "$MAX_MEMBERS" \
  "--bind-address" "$BIND_ADDRESS" \
  "--preferred-game" "$PREFERRED_GAME" \
  "--preferred-game-id" "$PREFERRED_GAME_ID" \
  "--ban-list-file" "$BAN_LIST_FILE" \
  "--log-file" "$LOG_FILE")

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
# Use process substitution to strip ANSI codes before appending to log
exec "${CMD[@]}" 2>&1 | tee >(sed -u 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")
