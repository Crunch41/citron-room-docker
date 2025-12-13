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
