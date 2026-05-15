#!/bin/sh
# TUFF-RADICAL: Surgical Bridge for KDE/Xwin
# Ensures Xwin finds the correct settings daemon regardless of Plasma version (5 or 6).

if [ -n "$TUFF_XWIN_PROFILE" ]; then
    # Detect installed KDE settings daemon
    KDED_BIN=$(command -v kded6 || command -v kded5 || echo "")
    if [ -n "$KDED_BIN" ]; then
        export TUFF_XWIN_HOST_SETTINGSD="$KDED_BIN"
    fi

    # Detect installed Plasma shell
    PLASMA_BIN=$(command -v startplasma-wayland || command -v startkde || echo "")
    if [ -n "$PLASMA_BIN" ]; then
        export TUFF_XWIN_HOST_SHELL="$PLASMA_BIN"
    fi
fi
