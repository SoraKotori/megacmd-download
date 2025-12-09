#!/bin/bash

# 可由環境變數覆蓋
MEGA_REMOTE_PATH="${MEGA_REMOTE_PATH:-/remotepath}"
MEGA_LOCAL_PATH="${MEGA_LOCAL_PATH:-/localpath}"

# 避免重複執行 cleanup
SHUTTING_DOWN=false

cleanup()
{
    $SHUTTING_DOWN && return
    SHUTTING_DOWN=true

    if ! pkill -0 mega-cmd-server; then
        echo "[INFO] Cleanup: mega-cmd-server not running, skip mega-quit"
        return
    fi

    echo "[INFO] Running cleanup: calling mega-quit..."
    if mega-quit; then
        echo "[INFO] Waiting for mega-cmd-server to exit..."

        # 等待 mega-cmd-server 完全退出，避免提早返回
        while pkill -0 mega-cmd-server; do
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

# 檢查本地路徑是否存在且為目錄
if [[ ! -d "$MEGA_LOCAL_PATH" ]]; then
    echo "[ERROR] Local path ${MEGA_LOCAL_PATH} does not exist or is not a directory."
    exit 1
fi

# 檢查帳密是否存在
if [[ -z "$MEGA_EMAIL" || -z "$MEGA_PASSWORD" ]]; then
    echo "[ERROR] No MEGA_EMAIL/MEGA_PASSWORD provided."
    exit 1
fi

mega_login_with_retry()
{
    local max_retry=10
    local sleep_sec=1
    local attempt
    local out
    local rc

    for ((attempt=1; attempt <= max_retry; attempt++)); do
        echo "[INFO] Attempting mega-login (attempt ${attempt}/${max_retry})..."

        # 成功通常沒有輸出，失敗會在 stderr
        out=$(mega-login "$MEGA_EMAIL" "$MEGA_PASSWORD" 2>&1)
        rc=$?

        if [[ $rc -eq 0 ]]; then
            echo "[INFO] mega-login succeeded."
            return 0
        fi

        # 已經有 session 視為成功
        if grep -q "Already logged in. Please log out first." <<< "$out"; then
            echo "[INFO] mega-login reports Already logged in."
            return 0
        fi

        # server 還在 auto-resume / login 中，等一下再試
        if grep -q "Command not valid while login in: login" <<< "$out"; then
            echo "[INFO] MEGAcmd is still logging in (auto-resume), will retry after ${sleep_sec}s."
            sleep "$sleep_sec"
            continue
        fi

        # 其他錯誤，直接失敗
        echo "$out"
        echo "[ERROR] mega-login failed with unexpected error."
        return 1
    done

    echo "[ERROR] mega-login failed after ${max_retry} attempts while login in."
    return 1
}

# 以 mega-login (含 retry) 作為啟動與登入流程
if ! mega_login_with_retry; then
    exit 1
fi

echo "[INFO] Login OK."

# 執行單向下載（remote -> local）
echo "[INFO] Running mega-get ${MEGA_REMOTE_PATH} -> ${MEGA_LOCAL_PATH}"
if ! mega-get "$MEGA_REMOTE_PATH" "$MEGA_LOCAL_PATH"; then
    echo "[ERROR] mega-get failed."
    exit 1
fi

echo "[INFO] Download finished."
