# Citron Room Server - Docker

Dockerized Citron dedicated room server with critical bug fixes.

## Quick Start

**Private Room**:
```bash
docker run -d -p 24872:24872/tcp -p 24872:24872/udp \
  -e ROOM_NAME="My Room" \
  -e PREFERRED_GAME_ID="01006A800016E000" \
  crunch41/citron-room-server
```

**Public Room**:
```bash
docker run -d -p 24872:24872/tcp -p 24872:24872/udp \
  -e ROOM_NAME="My Public Room" \
  -e USERNAME="your_username" \
  -e TOKEN="your-token" \
  -e WEB_API_URL="https://api.ynet-fun.xyz" \
  -e PREFERRED_GAME_ID="01006A800016E000" \
  crunch41/citron-room-server
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ROOM_NAME` | No | Citron Room | Room name |
| `ROOM_DESCRIPTION` | No | - | Room description |
| `USERNAME` | For public | - | Your username |
| `TOKEN` | For public | - | Your token |
| `WEB_API_URL` | For public | - | API URL |
| `PREFERRED_GAME` | No | Any Game | Game name |
| `PREFERRED_GAME_ID` | No | 0 | Game ID (hex) |
| `MAX_MEMBERS` | No | 16 | Max players |
| `PASSWORD` | No | - | Room password |
| `ENABLE_CITRON_MODS` | No | false | Allow mods |

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
      USERNAME: "your_username"
      TOKEN: "your-token"
      WEB_API_URL: "https://api.ynet-fun.xyz"
      PREFERRED_GAME_ID: "01006A800016E000"
    volumes:
      - ./data:/home/citron/.local/share/citron-room
    restart: unless-stopped
```

## Bug Fixes Included

This image fixes **5 critical bugs** in vanilla Citron that cause instant crashes with public room credentials.

**📋 See [PATCHES.md](PATCHES.md) for complete technical analysis and upstream patch details.**

## Common Game IDs

- Super Smash Bros. Ultimate: `01006A800016E000`
- Mario Kart 8 Deluxe: `0100152000022000`
- Splatoon 2: `01003BC0000A0000`
- Animal Crossing: `01006F8002326000`

## Building

```bash
git clone https://github.com/Crunch41/citron-room-docker.git
cd citron-room-docker
docker build -t citron-room-server .
```

**Image Size**: ~380MB  
**Auto-builds**: Daily when citron-room source files change

## For Citron Developers

If you want to apply these fixes to upstream Citron, see **[PATCHES.md](PATCHES.md)** for:
- Complete before/after code comparisons
- Root cause analysis for each bug
- GDB stack traces
- Why each fix is necessary

## Credits

- [Citron Emulator Team](https://git.citron-emu.org/Citron)
- Bug fixes by [Crunch41](https://github.com/Crunch41)
