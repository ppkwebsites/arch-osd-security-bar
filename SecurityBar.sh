#!/usr/bin/env bash
if pgrep -f "quickshell.*SecurityBar/SecurityBar.qml" >/dev/null; then
    pkill -f "quickshell.*"SecurityBar/SecurityBar.qml
else
    QT_QUICK_BACKEND=software quickshell -p ~/.config/quickshell/SecurityBar/SecurityBar.qml &
fi
