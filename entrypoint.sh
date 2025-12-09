#!/bin/bash
set -e

# 可由環境變數覆蓋
MEGA_REMOTE_PATH="${MEGA_REMOTE_PATH:-/remotepath}"
MEGA_LOCAL_PATH="${MEGA_LOCAL_PATH:-/localpath}"

# 避免重複執行 cleanup
SHUTTING_DOWN=false
cleanup() {
    $SHUTTING_DOWN && return
    SHUTTING_DOWN=true

    echo "[INFO] Running cleanup: calling mega-quit..."
    if mega-quit >/dev/null 2>&1; then
        echo "[INFO] Waiting for mega-cmd-server to exit..."

        # 等待 mega-cmd-server 完全退出，避免提早返回
        while pgrep -x "mega-cmd-server" >/dev/null 2>&1; do
            sleep 1
        done

        echo "[INFO] Cleanup done."
    else
        echo "[INFO] Cleanup: mega-quit not needed or failed (server may not be running)."
    fi
}

trap 'cleanup' EXIT
trap 'exit 130' INT   # Ctrl+C → 130
trap 'exit 143' TERM  # SIGTERM → 143 (=128+15)

echo "[INFO] MEGAcmd job starting..."
echo "[INFO] Remote path: ${MEGA_REMOTE_PATH}"
echo "[INFO] Local  path: ${MEGA_LOCAL_PATH}"

# 先用 mega-whoami 嘗試復原既有 session
if mega-whoami >/dev/null 2>&1; then
    echo "[INFO] Session resumed successfully."
else
    echo "[INFO] Not logged in yet. Trying to login..."

    if [[ -n "$MEGA_EMAIL" && -n "$MEGA_PASSWORD" ]]; then
        echo "[INFO] Logging in with MEGA_EMAIL..."
        if ! mega-login "$MEGA_EMAIL" "$MEGA_PASSWORD"; then
            echo "[ERROR] mega-login with MEGA_EMAIL/MEGA_PASSWORD failed."
            exit 1
        fi
    elif [[ -n "$MEGA_SESSION" ]]; then
        echo "[INFO] Logging in with MEGA_SESSION..."
        if ! mega-login --session "$MEGA_SESSION"; then
            echo "[ERROR] mega-login with MEGA_SESSION failed."
            exit 1
        fi
    else
        echo "[ERROR] No MEGA_EMAIL/MEGA_PASSWORD or MEGA_SESSION provided, and not logged in."
        exit 1
    fi

    echo "[INFO] Login OK."
fi

# 執行單向下載（remote -> local）
echo "[INFO] Running mega-get ${MEGA_REMOTE_PATH} -> ${MEGA_LOCAL_PATH}"
if ! mega-get "$MEGA_REMOTE_PATH" "$MEGA_LOCAL_PATH"; then
    echo "[ERROR] mega-get failed."
    exit 1
fi

echo "[INFO] Download finished."