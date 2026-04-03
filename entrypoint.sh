#!/bin/bash

set -euo pipefail

: "${MEGA_MANIFEST_FILE:?MEGA_MANIFEST_FILE is required}"

SHUTTING_DOWN=false

cleanup()
{
    $SHUTTING_DOWN && return
    SHUTTING_DOWN=true

    if ! pkill -0 mega-cmd-server; then
        echo "[INFO] Cleanup: mega-cmd-server not running, skip shutdown"
        return
    fi

    # 先取消傳輸再停 server。若先殺掉 server，可能留下不乾淨的傳輸狀態，
    # 讓下一次執行結果變得較不可預期。
    echo "[INFO] Running cleanup: cancelling all transfers..."
    mega-transfers -c -a || echo "[WARN] Failed to cancel transfers."

    echo "[INFO] Running cleanup: stopping mega-cmd-server..."
    if pkill mega-cmd-server; then
        echo "[INFO] Waiting for mega-cmd-server to exit..."
        while pkill -0 mega-cmd-server; do
            sleep 1
        done
        echo "[INFO] Cleanup done."
    else
        echo "[INFO] Cleanup: stopping mega-cmd-server failed."
    fi
}

require_command()
{
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "[ERROR] Required command not found: ${command_name}"
        exit 1
    }
}

load_secret_from_file()
{
    local value_var_name="$1"
    local file_var_name="$2"
    local secret_label="$3"
    local current_value="${!value_var_name:-}"
    local file_path="${!file_var_name:-}"

    if [[ -n "$current_value" ]]; then
        return 0
    fi

    if [[ -z "$file_path" ]]; then
        return 0
    fi

    if [[ ! -f "$file_path" ]]; then
        echo "[ERROR] ${file_var_name} points to a non-existent file: ${file_path}"
        exit 1
    fi

    printf -v "$value_var_name" '%s' "$(head -n 1 "$file_path")"

    if [[ -z "${!value_var_name}" ]]; then
        echo "[ERROR] ${secret_label} loaded from ${file_path} is empty."
        exit 1
    fi
}

resolve_download_path()
{
    local localpath="$1"

    # 這裡刻意不做額外展開：空字串代表目前工作目錄，
    # 相對路徑維持相對路徑，絕對路徑維持絕對路徑。
    if [[ -z "$localpath" ]]; then
        printf '.\n'
    else
        printf '%s\n' "$localpath"
    fi
}

validate_manifest()
{
    local manifest="$1"
    local target_count
    local index
    local invalid_link_count

    if [[ ! -f "$manifest" ]]; then
        echo "[ERROR] Manifest file ${manifest} does not exist."
        exit 1
    fi

    if ! yq -e 'has("targets") and (.targets | tag == "!!seq")' "$manifest" >/dev/null; then
        echo "[ERROR] Manifest must contain a root-level targets array."
        exit 1
    fi

    target_count="$(yq -r '.targets | length' "$manifest")"

    for ((index=0; index<target_count; index++)); do
        if ! yq -e ".targets[$index] | tag == \"!!map\"" "$manifest" >/dev/null; then
            echo "[ERROR] targets[$index] must be a mapping."
            exit 1
        fi

        if ! yq -e ".targets[$index] | (has(\"localpath\") and has(\"exportedlinks\"))" "$manifest" >/dev/null; then
            echo "[ERROR] targets[$index] must contain localpath and exportedlinks."
            exit 1
        fi

        if ! yq -e ".targets[$index].localpath | tag == \"!!str\"" "$manifest" >/dev/null; then
            echo "[ERROR] targets[$index].localpath must be a string."
            exit 1
        fi

        if ! yq -e ".targets[$index].exportedlinks | tag == \"!!seq\"" "$manifest" >/dev/null; then
            echo "[ERROR] targets[$index].exportedlinks must be an array."
            exit 1
        fi

        invalid_link_count="$(yq -r "[.targets[$index].exportedlinks[]? | select(tag != \"!!str\")] | length" "$manifest")"
        if [[ "$invalid_link_count" != "0" ]]; then
            echo "[ERROR] targets[$index].exportedlinks must contain only strings."
            exit 1
        fi
    done
}

mega_login_with_retry()
{
    local max_retry=10
    local sleep_sec=1
    local attempt
    local out
    local rc

    for ((attempt=1; attempt <= max_retry; attempt++)); do
        echo "[INFO] Attempting mega-login (attempt ${attempt}/${max_retry})..."

        # mega-login 在抓取節點進度時可能夾帶 NUL byte；先過濾掉，避免 command substitution 警告。
        if out="$(mega-login "$MEGA_EMAIL" "$MEGA_PASSWORD" 2>&1 | tr -d '\000')"; then
            echo "[INFO] mega-login succeeded."
            return 0
        else
            rc=$?
        fi

        if grep -q "Already logged in. Please log out first." <<< "$out"; then
            # 這個 job 模式可接受沿用既有 session，不視為錯誤。
            echo "[INFO] mega-login reports Already logged in."
            return 0
        fi

        if grep -q "Command not valid while login in: login" <<< "$out"; then
            # MEGAcmd 可能仍在恢復前次狀態；這裡重試可避免在短暫過渡期內誤判失敗。
            echo "[INFO] MEGAcmd is still logging in (auto-resume), will retry after ${sleep_sec}s."
            sleep "$sleep_sec"
            continue
        fi

        echo "$out"
        echo "[ERROR] mega-login failed with unexpected error."
        return 1
    done

    echo "[ERROR] mega-login failed after ${max_retry} attempts while login in."
    return 1
}

trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_command yq
require_command mega-login
require_command mega-get

echo "[INFO] MEGAcmd job starting..."
echo "[INFO] Manifest file: ${MEGA_MANIFEST_FILE}"

validate_manifest "$MEGA_MANIFEST_FILE"

item_count="$(yq -r '[.targets[].exportedlinks[]?] | length' "$MEGA_MANIFEST_FILE")"
echo "[INFO] Parsed ${item_count} download item(s)."

if [[ "$item_count" == "0" ]]; then
    echo "[INFO] No download items found."
    exit 0
fi

load_secret_from_file MEGA_EMAIL MEGA_EMAIL_FILE MEGA_EMAIL
load_secret_from_file MEGA_PASSWORD MEGA_PASSWORD_FILE MEGA_PASSWORD

if [[ -z "${MEGA_EMAIL:-}" || -z "${MEGA_PASSWORD:-}" ]]; then
    echo "[ERROR] No MEGA_EMAIL/MEGA_PASSWORD provided."
    exit 1
fi

if ! mega_login_with_retry; then
    exit 1
fi

echo "[INFO] Login OK."

failed_count=0
target_count="$(yq -r '.targets | length' "$MEGA_MANIFEST_FILE")"

for ((target_index=0; target_index<target_count; target_index++)); do
    localpath="$(yq -r ".targets[$target_index].localpath" "$MEGA_MANIFEST_FILE")"
    destination="$(resolve_download_path "$localpath")"
    link_count="$(yq -r ".targets[$target_index].exportedlinks | length" "$MEGA_MANIFEST_FILE")"

    if [[ -e "$destination" && ! -d "$destination" ]]; then
        echo "[ERROR] Destination path ${destination} exists and is not a directory."
        failed_count=$((failed_count + link_count))
        continue
    fi

    mkdir -p "$destination"

    for ((link_index=0; link_index<link_count; link_index++)); do
        exportedlink="$(yq -r ".targets[$target_index].exportedlinks[$link_index]" "$MEGA_MANIFEST_FILE")"

        echo "[INFO] Running mega-get ${exportedlink} -> ${destination}"
        if ! mega-get "$exportedlink" "$destination"; then
            echo "[ERROR] mega-get failed for ${exportedlink}"
            failed_count=$((failed_count + 1))
        fi
    done
done

if [[ $failed_count -gt 0 ]]; then
    echo "[ERROR] Download finished with ${failed_count} failure(s)."
    exit 1
fi

echo "[INFO] Download finished."
