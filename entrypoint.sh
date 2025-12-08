#!/bin/bash
set -e

# 可由環境變數覆蓋
MEGA_REMOTE_PATH="${MEGA_REMOTE_PATH:-/remotepath}"
MEGA_LOCAL_PATH="${MEGA_LOCAL_PATH:-/localpath}"

echo "[INFO] MEGAcmd job starting..."
echo "[INFO] Remote path: ${MEGA_REMOTE_PATH}"
echo "[INFO] Local  path: ${MEGA_LOCAL_PATH}"

# 用來避免 cleanup 被執行兩次
SHUTTING_DOWN=false
SERVER_PID=""

cleanup() {
    # 已經在關閉流程中，就不要再重複做
    $SHUTTING_DOWN && return
    SHUTTING_DOWN=true

    # 如果 server 根本沒起來或已經死掉，就不需要做任何 cleanup
    if [[ -z "${SERVER_PID:-}" ]] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "[INFO] Cleanup: mega-cmd-server is not running, nothing to do."
        return
    fi

    echo "[INFO] Running cleanup: calling mega-quit..."
    mega-quit || true

    echo "[INFO] Waiting for mega-cmd-server (PID $SERVER_PID) to exit..."
    wait "$SERVER_PID" || true

    echo "[INFO] Cleanup finished."
}

# 等待 mega-cmd-server ready
wait_for_server() {
    echo "[INFO] Waiting for mega-cmd-server to respond (max_retries=$1)..."

    for i in $(seq 1 "$1"); do
        # 先確認 server PID 存在而且還活著
        if [[ -z "${SERVER_PID:-}" ]] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "[ERROR] mega-cmd-server process exited unexpectedly."
            return 1
        fi

        # 再測試是否已 ready
        if mega-help >/dev/null 2>&1; then
            echo "[INFO] mega-cmd-server is ready (attempt $i)."
            return 0
        fi

        sleep 1
    done

    echo "[ERROR] mega-cmd-server did not respond in time."
    return 1
}

echo "[INFO] Starting mega-cmd-server..."
mega-cmd-server &
SERVER_PID=$!

# 在拿到 SERVER_PID 之後再設 trap，確保 cleanup 裡有 PID 可用
trap 'cleanup; exit 130' INT   # Ctrl+C → 130
trap 'cleanup; exit 143' TERM  # SIGTERM → 143 (=128+15)

# 等 server ready（最多重試 30 次，每次 1 秒）
if ! wait_for_server 30; then
    # 這裡代表 server 沒成功起來（或啟動後立刻死掉）
    # 因為 cleanup 會檢查到 SERVER_PID 不存在/已死，所以也算「沒東西可清理」
    echo "[ERROR] mega-cmd-server failed to start properly."
    exit 1
fi

# 檢查是否已登入；沒登入就用環境變數登入
if ! mega-whoami >/dev/null 2>&1; then
    echo "[INFO] Not logged in yet. Trying to login..."

    if [[ -n "$MEGA_EMAIL" && -n "$MEGA_PASSWORD" ]]; then
        echo "[INFO] Logging in with MEGA_EMAIL..."
        if ! mega-login "$MEGA_EMAIL" "$MEGA_PASSWORD"; then
            echo "[ERROR] mega-login with MEGA_EMAIL/MEGA_PASSWORD failed."
            cleanup
            exit 1
        fi
    elif [[ -n "$MEGA_SESSION" ]]; then
        echo "[INFO] Logging in with MEGA_SESSION..."
        if ! mega-login --session "$MEGA_SESSION"; then
            echo "[ERROR] mega-login with MEGA_SESSION failed."
            cleanup
            exit 1
        fi
    else
        echo "[ERROR] No MEGA_EMAIL/MEGA_PASSWORD or MEGA_SESSION provided, and not logged in."
        cleanup
        exit 1
    fi

    echo "[INFO] Login OK."
else
    echo "[INFO] Already logged in."
fi

# 執行單向下載（remote -> local）
echo "[INFO] Running mega-get ${MEGA_REMOTE_PATH} -> ${MEGA_LOCAL_PATH}"
if ! mega-get "$MEGA_REMOTE_PATH" "$MEGA_LOCAL_PATH"; then
    echo "[ERROR] mega-get failed."
    cleanup
    exit 1
fi

echo "[INFO] Download finished. Running cleanup..."
cleanup
exit 0
