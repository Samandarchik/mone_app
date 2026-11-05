#!/usr/bin/env bash
# KONAK POS — local demo backendni ishga tushirish.
#
#   ./scripts/run_demo.sh              — build qilib, :3000 da ishga tushiradi
#   PORT=3001 ./scripts/run_demo.sh    — boshqa portda
#
# MUHIM: demo rejimida sync O'CHIQ (SYNC_MODE=off) va Telegram bot O'CHIQ.
#   - sync o'chiq: demo buyurtmalari bulut/Windows bazasiga ketmaydi;
#   - telegram o'chiq: bitta bot tokenini ikkita server bir vaqtda so'rasa,
#     jonli bot ishlamay qoladi (getUpdates konflikti).
# Telegramni ataylab yoqmoqchi bo'lsangiz: DEMO_TELEGRAM=1 ./scripts/run_demo.sh

set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-3000}"
DB="${DB_URL:-postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable}"
LOG="${LOG_FILE:-./server_demo.log}"

echo "→ build..."
go build -o build/konak-demo ./cmd/server

if lsof -ti ":$PORT" >/dev/null 2>&1; then
  echo "→ $PORT portidagi eski jarayon to'xtatilmoqda..."
  lsof -ti ":$PORT" | xargs kill 2>/dev/null || true
  sleep 1
fi

TG=""
if [ "${DEMO_TELEGRAM:-0}" != "1" ]; then
  TG="TELEGRAM_BOT_TOKEN= TELEGRAM_ADMIN_CHAT_ID="
  echo "→ Telegram bot: O'CHIQ (DEMO_TELEGRAM=1 bilan yoqiladi)"
else
  echo "→ Telegram bot: YOQILGAN — diqqat, jonli bot bilan konflikt bo'lishi mumkin"
fi

echo "→ ishga tushmoqda: http://localhost:$PORT  (log: $LOG)"
env PORT="$PORT" DB_URL="$DB" SYNC_MODE=off NODE_ID=local CLOUD_WS_URL= $TG \
  nohup ./build/konak-demo >"$LOG" 2>&1 &

sleep 3
if curl -fsS "http://localhost:$PORT/api/health" >/dev/null; then
  echo "✓ Backend tayyor: http://localhost:$PORT/api"
  echo "  Salomatlik : http://localhost:$PORT/api/health"
  echo "  QR mijoz   : http://localhost:$PORT/customer/"
  echo "  Log        : tail -f $LOG"
else
  echo "✗ Ishga tushmadi. Log:"
  tail -30 "$LOG"
  exit 1
fi
