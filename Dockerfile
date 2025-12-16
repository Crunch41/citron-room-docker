# 1) Builder stage - PRODUCTION OPTIMIZED
###########################
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Base tools & certificates
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      build-essential \
      cmake \
      ninja-build \
      pkg-config \
      python3 \
      perl \
      autoconf \
      libtool \
      # Core libraries
      libboost-all-dev \
      libfmt-dev \
      liblz4-dev \
      libzstd-dev \
      libssl-dev \
      libopus-dev \
      zlib1g-dev \
      libenet-dev \
      nlohmann-json3-dev \
      llvm-dev \
      # Additional dependencies
      libudev-dev \
      libopenal-dev \
      glslang-tools \
      libavcodec-dev \
      libavfilter-dev \
      libavutil-dev \
      libswscale-dev \
      libswresample-dev \
      # X11 libraries
      libx11-dev \
      libxrandr-dev \
      libxinerama-dev \
      libxcursor-dev \
      libxi-dev \
      # mbedtls
      libmbedtls-dev \
      # Optional dependencies (suppress CMake warnings)
      libusb-1.0-0-dev \
      libgamemode-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone LATEST upstream with submodules
RUN git clone --recursive https://git.citron-emu.org/Citron/Emulator.git . && \
    echo "=== CITRON SOURCE ===" && \
    git log -1 --format="%H %s"

# ---------------------------------------------------------------------------
# PATCH 1: Fix stdin loop (prevents container hanging)
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/dedicated_room/citron_room.cpp")
content = p.read_text(encoding="utf-8")

match = re.search(r'while\s*\(\s*room->GetState\(\)\s*==\s*Network::Room::State::Open\s*\)\s*\{', content)

if match:
    start_idx = match.end()
    open_braces = 1
    end_idx = start_idx
    
    while open_braces > 0 and end_idx < len(content):
        if content[end_idx] == '{':
            open_braces += 1
        elif content[end_idx] == '}':
            open_braces -= 1
        end_idx += 1
        
    if open_braces == 0:
        replacement = '''while (room->GetState() == Network::Room::State::Open) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }'''
        
        content = content[:match.start()] + replacement + content[end_idx:]
        print("✓ Patched stdin loop")
        p.write_text(content, encoding="utf-8")
    else:
        print("ERROR: Could not find closing brace")
        exit(1)
else:
    print("ERROR: Could not find stdin loop")
    exit(1)
PY

# ---------------------------------------------------------------------------
# PATCH 2: Fix lobby_api_url (copy from web_api_url)
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/dedicated_room/citron_room.cpp")
content = p.read_text(encoding="utf-8")

pattern = re.compile(r'(\s*)(Settings::values\.web_api_url\s*=\s*web_api_url\s*;)')

def add_lobby_line(match):
    indent = match.group(1)
    original_line = match.group(2)
    return (indent + original_line + '\n' + 
            indent + 'Settings::values.lobby_api_url = Settings::values.web_api_url.GetValue();')

matches = pattern.findall(content)
if len(matches) >= 2:
    new_content = pattern.sub(add_lobby_line, content)
    p.write_text(new_content, encoding="utf-8")
    print(f"✓ Fixed lobby_api_url ({len(matches)} locations)")
else:
    print(f"ERROR: Expected 2 web_api_url assignments, found {len(matches)}")
    exit(1)
PY

# ---------------------------------------------------------------------------
# PATCH 3: Add error handling to Register()
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/web_service/announce_room_json.cpp")
content = p.read_text(encoding="utf-8")

if '#include <stdexcept>' not in content:
    content = content.replace(
        '#include <nlohmann/json.hpp>',
        '#include <stdexcept>\n#include <nlohmann/json.hpp>'
    )

pattern = re.compile(
    r'auto reply_json = nlohmann::json::parse\(result\.returned_data\);\s+'
    r'room = reply_json\.get<AnnounceMultiplayerRoom::Room>\(\);\s+'
    r'room_id = reply_json\.at\("id"\)\.get<std::string>\(\);',
    re.DOTALL
)

new_code = '''try {
        if (result.returned_data.empty()) {
            LOG_ERROR(WebService, "Registration response is empty");
            return WebService::WebResult{WebService::WebResult::Code::WrongContent, 
                                         "Empty response from server", ""};
        }
        
        auto reply_json = nlohmann::json::parse(result.returned_data);
        
        if (!reply_json.contains("id")) {
            LOG_ERROR(WebService, "Registration response missing 'id' field");
            return WebService::WebResult{WebService::WebResult::Code::WrongContent, 
                                         "Missing room ID in response", ""};
        }
        
        room = reply_json.get<AnnounceMultiplayerRoom::Room>();
        room_id = reply_json.at("id").get<std::string>();
        result.returned_data = room_id;
        
    } catch (const std::exception& e) {
        LOG_ERROR(WebService, "Registration parsing error: {}", e.what());
        return WebService::WebResult{WebService::WebResult::Code::WrongContent, 
                                     "Invalid JSON in response", ""};
    }'''

if pattern.search(content):
    content = pattern.sub(new_code, content)
    print("✓ Added Register() error handling")
    p.write_text(content, encoding="utf-8")
else:
    print("WARNING: Could not apply Register() fix")
PY

# ---------------------------------------------------------------------------
# PATCH 4: Thread safety wrapper
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path

p = Path("src/network/announce_multiplayer_session.cpp")
content = p.read_text(encoding="utf-8")

sig = "void AnnounceMultiplayerSession::AnnounceMultiplayerLoop() {"

if sig in content:
    parts = content.split(sig)
    before = parts[0] + sig
    after = parts[1]
    
    depth = 1
    split_idx = 0
    
    for i, char in enumerate(after):
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            
        if depth == 0:
            split_idx = i
            break
            
    if split_idx > 0:
        body = after[:split_idx]
        remainder = after[split_idx:]
        
        new_body = f'''
    try {{
{body}
    }} catch (const std::exception& e) {{
        LOG_ERROR(Network, "Announce thread crashed: {{}}", e.what());
    }} catch (...) {{
        LOG_ERROR(Network, "Announce thread crashed (unknown)");
    }}
'''
        content = before + new_body + remainder
        p.write_text(content, encoding="utf-8")
        print("✓ Added thread safety wrapper")
    else:
        print("WARNING: Could not find function end")
else:
    print("WARNING: Could not find AnnounceMultiplayerLoop")
PY

# ---------------------------------------------------------------------------
# PATCH 5: Fix username NULL crash (required_argument)
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path

p = Path("src/dedicated_room/citron_room.cpp")
content = p.read_text(encoding="utf-8")

original = '{"username", optional_argument, 0, \'u\'}'
replacement = '{"username", required_argument, 0, \'u\'}'

if original in content:
    content = content.replace(original, replacement)
    print("✓ Fixed username argument (required)")
    p.write_text(content, encoding="utf-8")
else:
    print("WARNING: Could not find username argument")
PY

# ---------------------------------------------------------------------------
# PATCH 6: Add moderator join logging
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/network/room.cpp")
content = p.read_text(encoding="utf-8")

# Find where we send join success and add logging
# We need to log BEFORE member is moved, so we'll look up from members list
search_pattern = """if (HasModPermission(event->peer)) {
        SendJoinSuccessAsMod(event->peer, preferred_fake_ip);
    } else {
        SendJoinSuccess(event->peer, preferred_fake_ip);
    }"""

replacement = """if (HasModPermission(event->peer)) {
        // Log moderator join (lookup from members list since member was moved)
        std::lock_guard lock(member_mutex);
        const auto mod_member = std::find_if(members.begin(), members.end(),
            [&event](const auto& m) { return m.peer == event->peer; });
        if (mod_member != members.end()) {
            LOG_INFO(Network, "User '{}' ({}) joined as MODERATOR", 
                     mod_member->nickname, mod_member->user_data.username);
        }
        SendJoinSuccessAsMod(event->peer, preferred_fake_ip);
    } else {
        SendJoinSuccess(event->peer, preferred_fake_ip);
    }"""

if search_pattern in content:
    content = content.replace(search_pattern, replacement)
    p.write_text(content, encoding="utf-8")
    print("✓ Added moderator join logging with correct member lookup")
else:
    print("WARNING: Could not apply moderator logging patch")
PY

# ---------------------------------------------------------------------------
# PATCH 7: Fix LAN moderator detection (check nickname when JWT fails)
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path

p = Path("src/network/room.cpp")
content = p.read_text(encoding="utf-8")

# Look for the specific pattern in HasModPermission function
# We want to add nickname check after the username check
search_string = """if (!room_information.host_username.empty() &&
        sending_member->user_data.username == room_information.host_username) { // Room host

        return true;
    }"""

replacement_string = """if (!room_information.host_username.empty() &&
        sending_member->user_data.username == room_information.host_username) { // Room host

        return true;
    }
    // Also check nickname for LAN connections (when JWT verification fails)
    if (!room_information.host_username.empty() &&
        sending_member->nickname == room_information.host_username) { // Room host (LAN)

        return true;
    }"""

if search_string in content:
    content = content.replace(search_string, replacement_string)
    p.write_text(content, encoding="utf-8")
    print("✓ Added LAN moderator detection (nickname check)")
else:
    print("WARNING: Could not find HasModPermission pattern")
    # Try to print what we can find for debugging
    if "HasModPermission" in content:
        print("INFO: HasModPermission function exists in file")
    if "room_information.host_username" in content:
        print("INFO: host_username check exists in file")
PY

# ---------------------------------------------------------------------------
# PATCH 8: Add IP-based LAN detection (improved accuracy)
# ---------------------------------------------------------------------------
# Add IsPrivateIP helper function to verify_user_jwt.cpp
RUN python3 - <<'PY'
from pathlib import Path

p = Path("src/web_service/verify_user_jwt.cpp")
content = p.read_text(encoding="utf-8")

# Add helper function to check if IP is private/LAN
search_for = '#include "web_service/verify_user_jwt.h"'

helper_function = '''#include "web_service/verify_user_jwt.h"

namespace {
// Check if an IP address is in a private network range
bool IsPrivateIP(const std::string& ip) {
    unsigned int o1, o2, o3, o4;
    if (sscanf(ip.c_str(), "%u.%u.%u.%u", &o1, &o2, &o3, &o4) != 4) {
        return false;  // Invalid IP format
    }
    
    // Check private ranges:
    // 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8
    if (o1 == 10) return true;
    if (o1 == 172 && o2 >= 16 && o2 <= 31) return true;
    if (o1 == 192 && o2 == 168) return true;
    if (o1 == 127) return true;
    
    return false;
}
} // namespace'''

if search_for in content:
    content = content.replace(search_for, helper_function)
    p.write_text(content, encoding="utf-8")
    print("✓ Added IsPrivateIP helper to verify_user_jwt.cpp")
else:
    print("WARNING: Could not find include statement")
PY

# Improve JWT verification error messaging
RUN python3 - <<'PY'
from pathlib import Path

p = Path("src/web_service/verify_user_jwt.cpp")
content = p.read_text(encoding="utf-8")

search_string = '''if (error) {
        LOG_INFO(WebService, "Verification failed: category={}, code={}, message={}",
                 error.category().name(), error.value(), error.message());
        return {};
    }'''

replacement_string = '''if (error) {
        // Provide context for JWT verification failures
        if (error.value() == 2) {
            LOG_INFO(WebService, "JWT signature verification skipped (error code 2)");
        } else {
            LOG_INFO(WebService, "JWT verification failed: category={}, code={}, message={}",
                     error.category().name(), error.value(), error.message());
        }
        return {};
    }'''

if search_string in content:
    content = content.replace(search_string, replacement_string)
    p.write_text(content, encoding="utf-8")
    print("✓ Improved JWT verification error messaging")
else:
    print("WARNING: Could not find JWT verification error pattern")
PY

# ---------------------------------------------------------------------------
# PATCH 9: Suppress harmless unknown IP errors in HandleLdnPacket
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/network/room.cpp")
content = p.read_text(encoding="utf-8")

# Find the unknown IP error log in HandleLdnPacket
# The actual source uses multi-line format with individual octets
pattern = r'LOG_ERROR\(Network,\s*\n\s*"Attempting to send to unknown IP address: "\s*\n\s*"\{\}\.\{\}\.\{\}\.\{\}",\s*\n\s*destination_address\[0\], destination_address\[1\], destination_address\[2\],\s*\n\s*destination_address\[3\]\);'

replacement = '''LOG_DEBUG(Network,
          "Packet to unknown IP (broadcasting instead): "
          "{}.{}.{}.{}",
          destination_address[0], destination_address[1], destination_address[2],
          destination_address[3]);'''

matches = re.findall(pattern, content)
if len(matches) >= 1:
    content = re.sub(pattern, replacement, content)
    p.write_text(content, encoding="utf-8")
    print(f"✓ Suppressed {len(matches)} unknown IP error(s) (moved to DEBUG level)")
else:
    print("INFO: PATCH 9 skipped (pattern not found in this Citron version)")
PY

# ---------------------------------------------------------------------------
# PATCH 10: Fix unknown IP errors with broadcast fallback
# ---------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/network/room.cpp")
content = p.read_text(encoding="utf-8")

# Find the error log + enet_packet_destroy pattern in HandleLdnPacket
# We'll replace the destroy with broadcast logic
pattern = r'(LOG_DEBUG\(Network,\s*\n\s*"Packet to unknown IP \(broadcasting instead\): "\s*\n\s*"\{\}\.\{\}\.\{\}\.\{\}",\s*\n\s*destination_address\[0\], destination_address\[1\], destination_address\[2\],\s*\n\s*destination_address\[3\]\);)\s*\n\s*enet_packet_destroy\(enet_packet\);'

replacement = r'''\1
                // Broadcast to all other members as fallback (safe for most LDN traffic)
                bool sent_packet = false;
                for (const auto& member : members) {
                    if (member.peer != event->peer) {
                        sent_packet = true;
                        enet_peer_send(member.peer, 0, enet_packet);
                    }
                }
                if (!sent_packet) {
                    enet_packet_destroy(enet_packet);
                }'''

if re.search(pattern, content):
    content = re.sub(pattern, replacement, content)
    p.write_text(content, encoding="utf-8")
    print("✓ Added broadcast fallback for unknown IP packets")
else:
    print("INFO: PATCH 10 skipped (requires PATCH 9 - pattern not found in this Citron version)")
PY

# Configure - RELEASE BUILD (optimized, no debug symbols)
RUN cmake -S . -B build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_QT=OFF \
      -DENABLE_QT_TRANSLATION=OFF \
      -DENABLE_SDL2=OFF \
      -DENABLE_WEB_SERVICE=ON \
      -DCITRON_ROOM=ON \
      -DCITRON_TESTS=OFF \
      -DCITRON_USE_BUNDLED_VCPKG=OFF \
      -DCITRON_CHECK_SUBMODULES=OFF

# Build and STRIP to reduce size
RUN cmake --build build --target citron-room -j"$(nproc)" && \
    strip build/bin/citron-room && \
    echo "=== BUILD COMPLETE ===" && \
    ls -lh build/bin/citron-room


###########################
# 2) Runtime stage - MINIMAL
###########################
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Runtime libraries only (no build tools, no debug tools)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libssl3 \
      libzstd1 \
      liblz4-1 \
      libopus0 \
      zlib1g \
      libboost-context1.83.0 \
      libenet7 \
      libfmt9 \
      libmbedtls14 \
      libopenal1 \
      libavcodec60 \
      libavfilter9 \
      libavutil58 \
      libswscale7 \
      libswresample4 \
      gzip \
    && rm -rf /var/lib/apt/lists/*

# Copy stripped binary
COPY --from=builder /src/build/bin/citron-room /usr/local/bin/citron-room

# Create non-root user
RUN useradd -m citron && \
    mkdir -p /home/citron/.local/share/citron-room && \
    chown -R citron:citron /home/citron

# Copy entrypoint
COPY --chown=citron:citron docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER citron
WORKDIR /home/citron

EXPOSE 24872/tcp
EXPOSE 24872/udp

VOLUME ["/home/citron/.local/share/citron-room"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
