#!/usr/bin/env bash
if pgrep -f "quickshell.*NetworkSecurityBar/NetworkSecurityBar.qml" >/dev/null; then
    pkill -f "quickshell.*NetworkSecurityBar/NetworkSecurityBar.qml"
else
    QT_QUICK_BACKEND=software quickshell -p ~/.config/quickshell/NetworkSecurityBar/NetworkSecurityBar.qml &
fi
