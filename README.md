# Citron Room Server - Docker

Dockerized Citron dedicated room server with critical bug fixes.

## Quick Start

### Private Room
```bash
docker run -d -p 24872:24872/tcp -p 24872:24872/udp \
  -e ROOM_NAME="My Room" \
  -e PREFERRED_GAME="Super Smash Bros" \
  crunch41/citron-room-server
```

### Public Room
```bash
docker run -d -p 24872:24872/tcp -p 24872:24872/udp \
  -e ROOM_NAME="My Public Room" \
  -e PREFERRED_GAME="Super Smash Bros" \
  -e USERNAME="your_username" \
  -e TOKEN="your-token" \
  -e WEB_API_URL="https://api.ynet-fun.xyz" \
  crunch41/citron-room-server
```

### Working Example (Unraid)
Real-world public room configuration running on Unraid:
```bash
docker run -d -p 24872:24872/tcp -p 24872:24872/udp \
  -e ROOM_NAME="My Awesome Server" \
  -e ROOM_DESCRIPTION="Welcome to my room!" \
  -e PREFERRED_GAME="Mario Kart 8" \
  -e PREFERRED_GAME_ID="0100152000022000" \
  -e USERNAME="YourUsername" \
  -e TOKEN="12345678-1234-1234-1234-123456789abc" \
  -e WEB_API_URL="https://api.ynet-fun.xyz" \
  -v /mnt/cache/appdata/citron-room:/home/citron/.local/share/citron-room \
  crunch41/citron-room-server
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ROOM_NAME` | **Yes** | - | Room name (shown in lobby) |
| `PREFERRED_GAME` | **Yes** | - | Game name (shown in lobby) |
| `ROOM_DESCRIPTION` | No | - | Room description |
| `USERNAME` | For public | - | Your username |
| `TOKEN` | For public | - | Your token (UUID) |
| `WEB_API_URL` | For public | - | API URL |
| `PREFERRED_GAME_ID` | No | 0 | Game ID (hex, e.g., 01006A800016E000) |
| `MAX_MEMBERS` | No | 16 | Max players (2-254) |
| `PASSWORD` | No | - | Room password |
| `BIND_ADDRESS` | No | 0.0.0.0 | Bind IP address |
| `PORT` | No | 24872 | Server port |
| `ENABLE_CITRON_MODS` | No | false | Allow moderators |

**Note**: `ROOM_NAME` and `PREFERRED_GAME` are required by Citron. Server will fail to start without them.

## Docker Compose

```yaml
version: '3.8'
services:
  citron-room:
    image: crunch41/citron-room-server:latest
    ports:
      - "24872:24872/tcp"
      - "24872:24872/udp"
    environment:
      ROOM_NAME: "My Server"
      PREFERRED_GAME: "Super Smash Bros"
      USERNAME: "your_username"
      TOKEN: "your-token"
      WEB_API_URL: "https://api.ynet-fun.xyz"
      PREFERRED_GAME_ID: "01006A800016E000"
    volumes:
      - ./data:/home/citron/.local/share/citron-room
    restart: unless-stopped
```

## Persistent Data

### Volume Mounting

**Required for**:
- ✅ Ban list persistence across restarts
- ✅ Log file persistence across restarts

```bash
-v /mnt/cache/appdata/citron-room:/home/citron/.local/share/citron-room
```

**Without volume mount**:
- ⚠️ Ban list resets on container restart
- ⚠️ Logs are lost on container restart

### Ban List Format

File: `/home/citron/.local/share/citron-room/ban_list.txt`

```
CitronRoom-BanList-1
BadUsername1
BadUsername2

192.168.1.100
10.0.0.50
```

**Structure**:
- Line 1: Magic header (required)
- Username bans (one per line)
- Empty line separator
- IP bans (one per line)

### Logs

- **Console**: `docker logs <container-name>`
- **File**: `/home/citron/.local/share/citron-room/citron-room.log` (requires volume)

**Logging Features** ✨:
- ✅ **Automatic rotation** - Rotates at 10MB, keeps last 7 files
- ✅ **Compression** - Old logs gzip compressed (saves space)
- ✅ **Clean format** - ANSI color codes stripped from file
- ✅ **ISO timestamps** - Each start includes ISO timestamp
- ✅ **Persistent** - Survives container restarts

**Log files**:
```
citron-room.log         # Current log (clean text)
citron-room.log.1.gz    # Previous rotation (compressed)
citron-room.log.2.gz    # 2nd rotation
...
citron-room.log.7.gz    # Oldest (auto-deleted when new rotation occurs)
```

## Bug Fixes Included

This image includes **16 patches** fixing critical bugs and improving security:

**Core Fixes (Patches 1-7)**:
1. ✅ **Container hanging** - Fixed stdin blocking loop
2. ✅ **Public room crash** - Fixed missing `lobby_api_url` initialization
3. ✅ **Username segfault** - Fixed NULL crash with username argument
4. ✅ **JSON errors** - Added error handling to `Register()`
5. ✅ **Thread crashes** - Added safety wrapper to announcement loop
6. ✅ **Moderator logging** - Shows when users join with mod privileges
7. ✅ **LAN moderator detection** - Enables mod powers on local connections

**Network Improvements (Patches 8-10)**:
8. ✅ **JWT error messaging** - Clearer error messages for verification failures
9. ✅ **Unknown IP error suppression** - Cleaner logs (moved to DEBUG)
10. ✅ **LDN packet loss fix** - Broadcast fallback for unknown IPs

**Security Patches (Patches 11-16)**:
11. ✅ **ServerLoop crash protection** - Exception handling in main loop
12. ✅ **DoS rate limiting** - Rate limits join requests per IP
13. ✅ **Race condition fix** - Thread-safe lock ordering documentation
14. ✅ **Thread-safe JWT key** - Mutex protection for public key fetch
15. ✅ **Malformed packet protection** - Validates packet size before parsing
16. ✅ **IP generation safeguard** - Prevents infinite loop edge case

### Moderator Features

**Server Owner Privileges**:
- Set `USERNAME` to your Citron username
- You'll automatically get moderator powers
- Works on LAN even when JWT verification fails

**Moderator Join Logs**:
```
[Network] User 'YourName' (YourName) joined as MODERATOR
```

**📋 See [PATCHES.md](PATCHES.md) for complete technical analysis.**

## Building

```bash
git clone https://github.com/Crunch41/citron-room-docker.git
cd citron-room-docker
docker build -t citron-room-server .
```

## For Citron Developers

If you want to apply these fixes to upstream Citron, see **[PATCHES.md](PATCHES.md)** for:
- Complete before/after code comparisons
- Root cause analysis for each bug
- GDB stack traces
- Why each fix is necessary

## Credits

- [Citron Emulator Team](https://git.citron-emu.org/Citron)
- Bug fixes by [Crunch41](https://github.com/Crunch41)
