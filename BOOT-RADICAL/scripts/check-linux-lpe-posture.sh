#!/bin/bash
set -euo pipefail

# KAIRO RADICAL Host Posture Gate
# Assessment for Linux Kernel LPE risk (e.g., CVE-2026-31431 / algif_aead)

STRICT_SECURITY="${STRICT_SECURITY:-0}"
KERNEL_VERSION=$(uname -r)
POSTURE="Accept"
REASON="No critical exposures detected."

echo "--- KAIRO Host Posture Assessment ---"
echo "Kernel: $KERNEL_VERSION"

# 1. Check if algif_aead is currently loaded
LOADED=$(lsmod | grep -q "^algif_aead" && echo "YES" || echo "NO")

# 2. Check if algif_aead is loadable
LOADABLE="UNKNOWN"
if command -v modinfo >/dev/null 2>&1; then
    if modinfo algif_aead >/dev/null 2>&1; then
        LOADABLE="YES"
    else
        LOADABLE="NO"
    fi
fi

# 3. Check for mitigations (blacklisting/install /bin/false)
MITIGATED="NO"
if grep -rE "blacklist[[:space:]]+algif_aead|install[[:space:]]+algif_aead[[:space:]]+/bin/false" /etc/modprobe.d/ >/dev/null 2>&1; then
    MITIGATED="YES"
fi

echo "algif_aead loaded: $LOADED"
echo "algif_aead loadable: $LOADABLE"
echo "Mitigation detected: $MITIGATED"

# Decision Logic
if [ "$LOADED" = "YES" ]; then
    POSTURE="Reject"
    REASON="algif_aead is active on a potentially vulnerable kernel."
elif [ "$LOADABLE" = "YES" ] && [ "$MITIGATED" = "NO" ]; then
    POSTURE="Defer"
    REASON="algif_aead is loadable without mitigation. Disable or blacklist to accept."
    if [ "$STRICT_SECURITY" = "1" ]; then
        POSTURE="Fatal"
        REASON="STRICT_SECURITY violation: algif_aead is loadable and unmitigated."
    fi
elif [ "$LOADABLE" = "NO" ] || [ "$MITIGATED" = "YES" ]; then
    POSTURE="Accept"
    REASON="algif_aead is either unavailable or mitigated."
fi

echo "--------------------------------------"
echo "KAIRO Posture Decision: $POSTURE"
echo "Reason: $REASON"

if [ "$POSTURE" = "Fatal" ]; then
    exit 1
fi

exit 0
