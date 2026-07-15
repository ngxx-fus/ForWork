#!/usr/bin/env zsh

###############################################################################
# Watch mode: continuously sync *.map, *.srec from Coder workspace.
# 
# On each iteration:
#   1. rsync --checksum  → transfer only if content differs
#   2. If any file was transferred → re-scan .map files for _SEGGER_RTT
#   3. If nothing changed → skip re-scan, sleep, and check again
#
# Press Ctrl+C to stop.
###############################################################################

set -u
setopt NULL_GLOB

# ---------- Configuration ----------
DEST_DIR="/mnt/c/Users/phu.nguyen-thanh/Downloads/Test/TestSpace"
WORKSPACE="meow"
REMOTE_HOST="coder.${WORKSPACE}"
BASE="/home/coder/workspace/peaks/build"

PATHS=(
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_out_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_out_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_pwm_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pc_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_pwm_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_tz_typical_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_wp_test_gptclk_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_wp_test_pclkd_debug"
	"${BASE}/r_gpt/ra8d1_ek/gcc/build_r_gpt_wp_test_pclkd_debug"
	"${BASE}/r_gpt_s/ra8d1_ek/gcc/build_r_gpt_s_typical_debug"
)

# Poll interval (seconds) between sync attempts
readonly WATCH_INTERVAL=2.0

# ---------- Colors ----------
readonly RESET=$'\033[0m'
readonly GREEN=$'\033[0;32m'
readonly CYAN=$'\033[0;36m'
readonly YELLOW=$'\033[0;33m'
readonly RED=$'\033[0;31m'
readonly BLUE=$'\033[0;34m'
readonly MAGENTA=$'\033[0;35m'

# ---------- Coder CLI ----------
readonly CODER_CLI="/usr/local/bin/coder"
readonly CODER_CFG="/home/fus/.config/coderv2"

# ---------- Silent ProxyCommand ----------
PROXY_CMD="sh -c '${CODER_CLI} --global-config ${CODER_CFG} ssh --stdio ${WORKSPACE} 2>/dev/null'"
SSH_CMD="ssh -T -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -o ProxyCommand=\"${PROXY_CMD}\""

mkdir -p "${DEST_DIR}"

# ---------- Graceful shutdown ----------
cleanup() {
    echo ""
    echo "${MAGENTA}Watch mode stopped by user.${RESET}"
    exit 0
}
trap cleanup INT TERM

# ---------- Function: find _SEGGER_RTT in all *.map in pwd ----------
find_rtt_address() {
    echo "${CYAN}\nFinding _SEGGER_RTT address in $(pwd)...${RESET}"
    local map_files=(./*.map)

    if (( ${#map_files[@]} == 0 )); then
        echo "${YELLOW}  No .map files found in $(pwd)${RESET}"
        return
    fi

    for file in "${map_files[@]}"; do
        local addr=$(grep -E '\b_SEGGER_RTT\b' "${file}" 2>/dev/null \
                     | grep -oE '0x[0-9A-Fa-f]{8}' \
                     | grep -vE '^0x0+$' \
                     | head -n1)
        if [[ -n "${addr}" ]]; then
            echo "${GREEN}  ${file:t}: ${addr}${RESET}"
        else
            echo "${YELLOW}  ${file:t}: not found${RESET}"
        fi
    done
    echo ""
}

# ---------- Function: sync and detect changes (Parallel with Throttling) ----------
# Returns 0 if any file was updated, 1 if nothing changed, 2 on error
sync_files() {
    local total_changed=0
    local total_failed=0
    local tmp_dir=$(mktemp -d)
    
    # Maximum number of parallel SSH/rsync connections allowed at once
    local MAX_CONCURRENT=8 
    local batch_pids=()
    local batch_indices=()

	echo "${YELLOW}START SYNC FROM [$WORKSPACE]${RESET}"

    for i in {1..${#PATHS[@]}}; do
        local p="${PATHS[i]}"
        local tmp_log="${tmp_dir}/log_${i}"

        # Dispatch background task
        rsync -rz --checksum \
            --no-times --no-perms --no-owner --no-group --omit-dir-times \
            --itemize-changes \
            -e "${SSH_CMD}" \
            --include='*.map' --include='*.srec' --exclude='*' \
            "${REMOTE_HOST}:${p}/" "${DEST_DIR}/" \
            > "${tmp_log}" 2>/dev/null &
        
        # Save PID and corresponding index
        batch_pids+=($!)
        batch_indices+=($i)

        # Wait and process when batch is full OR at the last element
        if (( ${#batch_pids[@]} >= MAX_CONCURRENT || i == ${#PATHS[@]} )); then
            for idx in {1..${#batch_pids[@]}}; do
                local pid="${batch_pids[idx]}"
                local orig_i="${batch_indices[idx]}"
                local target_path="${PATHS[orig_i]}"
                local log_file="${tmp_dir}/log_${orig_i}"

                # Suppress wait error outputs if job already reaped
                wait "${pid}" 2>/dev/null
                local rc=$?

                # Error handling for the specific path
                if [[ ${rc} -ne 0 ]]; then
                    echo "${RED}  rsync failed for ${target_path:t} (exit ${rc})${RESET}"
                    total_failed=$((total_failed + 1))
                    continue
                fi
                
                # Check for successfully transferred files
                local changed
                changed=$(grep -cE '^>f' "${log_file}" 2>/dev/null) || changed=0
                if (( changed > 0 )); then
                    echo "${GREEN}  ${target_path:t}: ${changed} file(s) updated${RESET}"
                    grep -E '^>f' "${log_file}" | awk '{print "    ↳ " $NF}' | while read -r line; do
                        echo "${BLUE}${line}${RESET}"
                    done
                    total_changed=$((total_changed + changed))
                fi
            done
            
            # Reset batch buffers for the next cycle
            batch_pids=()
            batch_indices=()
        fi
    done

    rm -rf "${tmp_dir}"

    if (( total_failed > 0 )); then
        return 2
    elif (( total_changed > 0 )); then
        return 0
    else
        return 1
    fi
}

# ---------- Main watch loop ----------
echo "${MAGENTA}=== Watch mode started (interval: ${WATCH_INTERVAL}s) ===${RESET}"
echo "${MAGENTA}    Press Ctrl+C to stop${RESET}"
echo ""

changed_in_last_iteration=1
iteration=0
while true; do
    iteration=$((iteration + 1))
    timestamp=$(date '+%H:%M:%S')
    echo "${CYAN}[${timestamp}] Iteration #${iteration}: checking for updates...${RESET}"
    
	if (( $changed_in_last_iteration == 1 )); then
		clear
		find_rtt_address
		changed_in_last_iteration=0
	fi
    sync_files 1>/dev/null
    rc=$?
    
    case ${rc} in
        0)
            # Files changed → rescan for _SEGGER_RTT
            find_rtt_address
			changed_in_last_iteration=1
            ;;
        1)
            # No changes
            echo "${YELLOW}  No changes detected.${RESET}"
			changed_in_last_iteration=0
            ;;
        2)
            # Error occurred (partial or full failure)
            echo "${RED}  Sync error, will retry next iteration.${RESET}"
			changed_in_last_iteration=1
            ;;
    esac

    echo ""
    sleep "${WATCH_INTERVAL}"
done
