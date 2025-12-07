#!/bin/bash
set -e

# 可由環境變數覆蓋
MEGA_REMOTE_PATH="${MEGA_REMOTE_PATH:-/remote/path}"
MEGA_LOCAL_PATH="${MEGA_LOCAL_PATH:-/local-download}"

echo "[INFO] MEGAcmd job starting..."
echo "[INFO] Remote path: ${MEGA_REMOTE_PATH}"
echo "[INFO] Local  path: ${MEGA_LOCAL_PATH}"

cleanup() {
  echo "[INFO] Caught signal, calling mega-quit..."
  mega-quit >/dev/null 2>&1 || true
  exit 0
}
trap cleanup TERM INT

wait_for_server() {
  local max_retries="${1:-30}"
  echo "[INFO] Waiting for mega-cmd-server to respond..."
  for i in $(seq 1 "$max_retries"); do
    # 只要 mega-help 有回應，就表示 server 已 ready（不管有沒有登入）
    if mega-help >/dev/null 2>&1; then
      echo "[INFO] mega-cmd-server is ready (attempt $i)."
      return 0
    fi

    # server process 死掉就直接失敗
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      echo "[ERROR] mega-cmd-server process exited unexpectedly."
      return 1
    fi

    sleep 1
  done

  echo "[ERROR] mega-cmd-server did not respond in time."
  return 1
}

echo "[INFO] Starting mega-cmd-server..."
mega-cmd-server &
SERVER_PID=$!

wait_for_server 30

# 檢查是否已登入；沒登入就用 Secret 提供的帳密 / session 登入
if ! mega-whoami >/dev/null 2>&1; then
  echo "[INFO] Not logged in yet. Trying to login..."

  if [[ -n "$MEGA_EMAIL" && -n "$MEGA_PASSWORD" ]]; then
    echo "[INFO] Logging in with MEGA_EMAIL..."
    mega-login "$MEGA_EMAIL" "$MEGA_PASSWORD"
  elif [[ -n "$MEGA_SESSION" ]]; then
    echo "[INFO] Logging in with MEGA_SESSION..."
    mega-login --session "$MEGA_SESSION"
  else
    echo "[ERROR] No MEGA_EMAIL/MEGA_PASSWORD or MEGA_SESSION provided, and not logged in."
    exit 1
  fi

  echo "[INFO] Login OK."
else
  echo "[INFO] Already logged in."
fi

# 執行單向下載（remote -> local）
echo "[INFO] Running mega-get ${MEGA_REMOTE_PATH} -> ${MEGA_LOCAL_PATH}"
mega-get "$MEGA_REMOTE_PATH" "$MEGA_LOCAL_PATH" --recursive

echo "[INFO] Download finished. Calling mega-quit..."
mega-quit || true

# 等待 server 真的關閉，避免殭屍行程
wait "$SERVER_PID" || true

echo "[INFO] MEGAcmd job completed successfully."
