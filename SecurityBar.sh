#!/usr/bin/env bash

# Define the path to your QML file
QML_PATH="$HOME/.config/quickshell/SecurityBar/SecurityBar.qml"

# Check if quickshell is already running THAT SPECIFIC file
if pgrep -f "quickshell.*$QML_PATH" > /dev/null; then
    # If found, kill it (Close)
    pkill -f "quickshell.*$QML_PATH"
else
    # If not found, launch it (Open)
    QT_QUICK_BACKEND=software quickshell -p "$QML_PATH" &
fi
