#!/bin/sh
# Mac / Linux: double-click may not work; run in Terminal:  sh run.sh
cd "$(dirname "$0")" || exit 1
if command -v python3 >/dev/null 2>&1; then
    exec python3 app.py
elif command -v python >/dev/null 2>&1; then
    exec python app.py
else
    echo "Python 3 was not found. Install it from https://www.python.org/downloads/"
    exit 1
fi
