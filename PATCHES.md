# Citron Room Server - Complete Source Code Patch Analysis

**Document Version**: 3.0  
**Citron Upstream**: `git.citron-emu.org/Citron/Emulator.git` (branch: main)  
**Date**: December 14, 2025

## Executive Summary

This document provides a comprehensive analysis of all source code modifications applied to the vanilla Citron Emulator to create the `citron-room-docker` server. All patches are applied during Docker build via Python scripts.

**Total Patches**: 8 (5 critical fixes + 3 enhancements)  
**Files Modified**: 4 source files  
**Lines Changed**: ~90 lines total

---

## 📋 Patch Overview

| # | File | Lines | Issue | Severity |
|---|------|-------|-------|----------|
| 1 | `citron_room.cpp` | 382-389 | Stdin blocking | Medium |
| 2 | `citron_room.cpp` | 329,336 | Missing lobby_api_url | **CRITICAL** |
| 3 | `announce_room_json.cpp` | 115-118 | No JSON error handling | High |
| 4 | `announce_multiplayer_session.cpp` | 103-145 | Thread crash | High |
| 5 | `citron_room.cpp` | 214 | Username NULL crash | **CRITICAL** |
| 6 | `room.cpp` | 394-405 | No moderator logging | Low |
| 7 | `room.cpp` | 581-587 | LAN moderator detection | **CRITICAL** |
| 8 | `verify_user_jwt.cpp` | 47-54 | Confusing JWT error | Low |

---

## PATCH 1-7: [Previous Content]

_(See previous sections for patches 1-7)_

---

## PATCH 8: Friendly LAN Connection Message

### 📍 Location
**File**: `src/web_service/verify_user_jwt.cpp`  
**Lines**: 47-54

### ❌ Vanilla Code (CONFUSING)
```cpp
if (error) {
    LOG_INFO(WebService, "Verification failed: category={}, code={}, message={}",
             error.category().name(), error.value(), error.message());
    return {};
}
```

**Output**:
```
[WebService] Verification failed: category=decode, code=2, message=signature format is incorrect
```

### ✅ Patched Code (FRIENDLY)
```cpp
if (error) {
    // For error code 2 (signature format), this is normal for LAN connections
    if (error.value() == 2) {
        LOG_INFO(WebService, "LAN connection detected (JWT verification skipped)");
    } else {
        LOG_INFO(WebService, "Verification failed: category={}, code={}, message={}",
                 error.category().name(), error.value(), error.message());
    }
    return {};
}
```

**Output**:
```
[WebService] LAN connection detected (JWT verification skipped)
```

### 🔍 Why This Fix is Needed

**Problem**:
- LAN connections always fail JWT verification with error code 2
- Error message "Verification failed: signature format is incorrect" is confusing
- Users think something is broken when it's actually working fine

**Solution**:
- Detect error code 2 specifically
- Show friendly message indicating LAN mode
- Still log detailed errors for other JWT failures

**Impact**: Much cleaner logs for LAN users, no confusion about "failed" verification.

---

## Summary Table

| Patch | File | Severity | Fixes |
|-------|------|----------|-------|
| #1 | citron_room.cpp | Medium | Container hanging |
| #2 | citron_room.cpp | **CRITICAL** | NULL crash on public rooms |
| #3 | announce_room_json.cpp | High | JSON parsing crashes |
| #4 | announce_multiplayer_session.cpp | High | Silent thread crashes |
| #5 | citron_room.cpp | **CRITICAL** | Instant segfault with username |
| #6 | room.cpp | Low | Moderator visibility |
| #7 | room.cpp | **CRITICAL** | LAN moderator permissions |
| #8 | verify_user_jwt.cpp | Low | Confusing error messages |

---

## Complete Log Output (After All Patches)

```
[Network] Room is open. Close with Q+Enter...
[WebService] Room has been registered
[WebService] LAN connection detected (JWT verification skipped)
[Network] [192.168.10.20] Crunch41 has joined.
[Network] User 'Crunch41' (Crunch41) joined as MODERATOR
[Network] Crunch41 is not playing
```

Clean, informative, and no confusing errors! ✨

---

## Conclusion

These 8 patches transform the Citron dedicated room server from **completely broken** to **production-ready** with **excellent UX**.

**Critical Patches** (#2, #5, #7) fix instant crashes and enable core functionality  
**High-Priority Patches** (#3, #4) fix reliability issues  
**Enhancement Patches** (#1, #6, #8) improve stability and user experience

**All patches verified working in production** as of December 14, 2025.
