#!/bin/bash
# Double-click this file in Finder to start Vinyl Crisis.
# It starts a local web server (required — opening index.html directly
# via file:// blocks the fetches this app needs) and opens your browser.
cd "$(dirname "$0")"
PORT=8000

while lsof -i ":$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
  PORT=$((PORT + 1))
done

echo "Starting Vinyl Crisis at http://localhost:$PORT/index.html"
echo "Keep this window open while you use the app."
echo "Close this window (or press Ctrl+C) to stop it."
echo ""

(sleep 1 && open "http://localhost:$PORT/index.html") &
python3 -m http.server "$PORT"
