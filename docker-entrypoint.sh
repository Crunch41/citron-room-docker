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

# Determine mode
MODE="Private"
if [ -n "$USERNAME" ] && [ -n "$TOKEN" ] && [ -n "$WEB_API_URL" ]; then
    MODE="Public (announcing every 15s)"
fi

# Print configuration
echo "==================================="
echo "Citron Room Server Starting"
echo "==================================="
echo "Configuration:"
echo "  Room Name: $ROOM_NAME"
echo "  Port: $PORT"
echo "  Max Members: $MAX_MEMBERS (max: 254)"
echo "  Bind Address: $BIND_ADDRESS"
echo "  Ban List: $BAN_LIST_FILE"
echo "  Log File: $LOG_FILE"
echo "  Network Version: 1"
echo "  Mode: $MODE"
echo "==================================="

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

# Execute
exec "${CMD[@]}"
