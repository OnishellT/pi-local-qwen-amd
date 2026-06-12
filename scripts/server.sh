#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=profiles.sh
source "${SCRIPT_DIR}/profiles.sh"

PREFIX="${PI_LOCAL_QWEN_AMD_HOME:-${HOME}/.pi/local-qwen-amd}"
HOST="${PI_LOCAL_QWEN_AMD_HOST:-127.0.0.1}"
PORT="${PI_LOCAL_QWEN_AMD_PORT:-8004}"
BASE_URL="http://${HOST}:${PORT}"
DEFAULT_MODEL="${PI_LOCAL_QWEN_AMD_DEFAULT_MODEL:-qwopus35-9b-coder-mtp-q5-100k}"
LLAMA_SERVER="${PI_LOCAL_QWEN_AMD_LLAMA_SERVER:-${PREFIX}/llama.cpp/build-vulkan/bin/llama-server}"
STATE_DIR="${PREFIX}/run"
LOG_DIR="${PREFIX}/logs"
PID_FILE="${STATE_DIR}/server.pid"
STATE_FILE="${STATE_DIR}/server.env"
LOG_FILE="${LOG_DIR}/server.log"
STARTUP_TIMEOUT="${PI_LOCAL_QWEN_AMD_STARTUP_TIMEOUT:-120}"
DEVICE="${PI_LOCAL_QWEN_AMD_DEVICE:-Vulkan1}"
THREADS="${PI_LOCAL_QWEN_AMD_THREADS:-12}"
THREADS_BATCH="${PI_LOCAL_QWEN_AMD_THREADS_BATCH:-24}"
CACHE_TYPE_K="${PI_LOCAL_QWEN_AMD_CACHE_TYPE_K:-f16}"
CACHE_TYPE_V="${PI_LOCAL_QWEN_AMD_CACHE_TYPE_V:-f16}"
SPEC_DRAFT_TYPE_K="${PI_LOCAL_QWEN_AMD_SPEC_DRAFT_TYPE_K:-q8_0}"
SPEC_DRAFT_TYPE_V="${PI_LOCAL_QWEN_AMD_SPEC_DRAFT_TYPE_V:-q8_0}"
NO_MMAP="${PI_LOCAL_QWEN_AMD_NO_MMAP:-true}"
KV_UNIFIED="${PI_LOCAL_QWEN_AMD_KV_UNIFIED:-false}"

mkdir -p "${STATE_DIR}" "${LOG_DIR}"

normalize_profile() {
  case "${1:-}" in
    qwen|qwen35-9b-mtp-fast) echo qwen35-9b-mtp-fast ;;
    qwopus|coder|qwopus35-9b-coder-mtp-q5-100k) echo qwopus35-9b-coder-mtp-q5-100k ;;
    "") echo "${DEFAULT_MODEL}" ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<EOF
Usage: pi-local-qwen-amd-server <start|stop|restart|status|logs|url|profiles> [qwen|qwopus|PROFILE]

Profiles:
  qwen35-9b-mtp-fast              Qwen3.5-9B MTP Q4_K_M fast
  qwopus35-9b-coder-mtp-q5-100k  Qwopus3.5-9B Coder MTP Q5_K_M 100K

Environment overrides:
  PI_LOCAL_QWEN_AMD_HOME          install prefix (default: ~/.pi/local-qwen-amd)
  PI_LOCAL_QWEN_AMD_PORT          server port (default: 8004)
  PI_LOCAL_QWEN_AMD_DEVICE        Vulkan device (default: Vulkan1; set Vulkan0 if your AMD dGPU is first)
  PI_LOCAL_QWEN_AMD_KEEP_SERVER=1 extension leaves server running on shutdown/model change
EOF
}

healthy() { curl -fsS --max-time 2 "${BASE_URL}/health" >/dev/null 2>&1; }
pid_running() { [[ -f "${PID_FILE}" ]] || return 1; local pid; pid="$(cat "${PID_FILE}" 2>/dev/null || true)"; [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; }
port_pid() { pgrep -af llama-server 2>/dev/null | grep -F -- "--port ${PORT}" | awk '{print $1}' | head -1 || true; }

current_profile() { [[ -f "${STATE_FILE}" ]] && sed -n 's/^profile=//p' "${STATE_FILE}" | tail -1; }

start_server() {
  local profile model_path ctx fit_ctx batch ubatch draft_n p_min max_tokens label
  profile="$(normalize_profile "${1:-}")" || { echo "unknown profile: ${1:-}" >&2; usage >&2; return 2; }
  label="$(profile_label "$profile")"
  model_path="${PI_LOCAL_QWEN_AMD_MODEL_PATH:-$(profile_model_path "${PREFIX}" "$profile")}" 
  ctx="${PI_LOCAL_QWEN_AMD_CTX_SIZE:-$(profile_ctx "$profile")}"; fit_ctx="${PI_LOCAL_QWEN_AMD_FIT_CTX:-${ctx}}"
  batch="${PI_LOCAL_QWEN_AMD_BATCH_SIZE:-$(profile_batch "$profile")}"; ubatch="${PI_LOCAL_QWEN_AMD_UBATCH_SIZE:-$(profile_ubatch "$profile")}" 
  draft_n="${PI_LOCAL_QWEN_AMD_MTP_DRAFT_N:-$(profile_mtp_draft_n "$profile")}"; p_min="${PI_LOCAL_QWEN_AMD_SPEC_DRAFT_P_MIN:-$(profile_spec_p_min "$profile")}" 
  max_tokens="$(profile_max_tokens "$profile")"

  if healthy; then
    if [[ "$(current_profile 2>/dev/null || true)" == "${profile}" ]]; then echo "Already healthy: ${BASE_URL}/v1 (${profile})"; return 0; fi
    echo "Different profile is running; restarting as ${profile}" >&2
    stop_server >/dev/null 2>&1 || true
  fi
  [[ -x "${LLAMA_SERVER}" ]] || { echo "llama-server not found: ${LLAMA_SERVER}. Run: pi-local-qwen-amd-install --model ${profile}" >&2; return 1; }
  [[ -f "${model_path}" ]] || { echo "model not found: ${model_path}. Run: pi-local-qwen-amd-install --model ${profile}" >&2; return 1; }

  stop_server >/dev/null 2>&1 || true
  : > "${LOG_FILE}"
  args=(
    --model "${model_path}" --alias "${profile}" --host "${HOST}" --port "${PORT}"
    --ctx-size "${ctx}" --parallel 1 --threads "${THREADS}" --threads-batch "${THREADS_BATCH}"
    --batch-size "${batch}" --ubatch-size "${ubatch}" --device "${DEVICE}"
    --fit on --fit-target 1024 --fit-ctx "${fit_ctx}" --flash-attn on
    --cache-type-k "${CACHE_TYPE_K}" --cache-type-v "${CACHE_TYPE_V}"
    --spec-type draft-mtp --spec-draft-n-max "${draft_n}" --spec-draft-p-min "${p_min}" --spec-draft-p-split 0.10
    --spec-draft-type-k "${SPEC_DRAFT_TYPE_K}" --spec-draft-type-v "${SPEC_DRAFT_TYPE_V}"
    --spec-ngram-mod-n-match 24 --spec-ngram-mod-n-min 48 --spec-ngram-mod-n-max 64
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --presence-penalty 0.0 --repeat-penalty 1.0
    --jinja --reasoning on --cont-batching --cache-prompt --metrics
  )
  [[ "${NO_MMAP}" == "true" || "${NO_MMAP}" == "1" || "${NO_MMAP}" == "on" ]] && args+=(--no-mmap)
  [[ "${KV_UNIFIED}" == "true" || "${KV_UNIFIED}" == "1" || "${KV_UNIFIED}" == "on" ]] && args+=(--kv-unified)

  nohup "${LLAMA_SERVER}" "${args[@]}" >>"${LOG_FILE}" 2>&1 &
  echo $! > "${PID_FILE}"
  for ((i=0; i<STARTUP_TIMEOUT; i++)); do
    if healthy; then
      cat > "${STATE_FILE}" <<EOF
profile=${profile}
label=${label}
base_url=${BASE_URL}/v1
pid=$(cat "${PID_FILE}")
log=${LOG_FILE}
model_path=${model_path}
llama_server=${LLAMA_SERVER}
ctx_size=${ctx}
max_tokens=${max_tokens}
device=${DEVICE}
batch_size=${batch}
ubatch_size=${ubatch}
mtp_draft_n=${draft_n}
EOF
      echo "Started ${profile} (${label}): ${BASE_URL}/v1"; echo "Log: ${LOG_FILE}"; return 0
    fi
    if ! pid_running; then echo "llama-server exited during startup" >&2; tail -120 "${LOG_FILE}" >&2 || true; return 1; fi
    sleep 1
  done
  echo "server did not become healthy: ${BASE_URL}/health" >&2; echo "Log: ${LOG_FILE}" >&2; return 1
}

stop_server() {
  if pid_running; then kill -TERM "$(cat "${PID_FILE}")" 2>/dev/null || true; fi
  local pid; pid="$(port_pid)"; [[ -n "${pid}" ]] && kill -TERM "${pid}" 2>/dev/null || true
  for _ in {1..40}; do pid_running || [[ -z "$(port_pid)" ]] && break; sleep 0.25; done
  if pid_running; then kill -KILL "$(cat "${PID_FILE}")" 2>/dev/null || true; fi
  pid="$(port_pid)"; [[ -n "${pid}" ]] && kill -KILL "${pid}" 2>/dev/null || true
  rm -f "${PID_FILE}" "${STATE_FILE}"
}

status_server() { if healthy; then echo "healthy: ${BASE_URL}/v1"; else echo "not healthy: ${BASE_URL}/v1"; fi; [[ -f "${STATE_FILE}" ]] && cat "${STATE_FILE}"; }

case "${1:-status}" in
  start) start_server "${2:-}" ;;
  stop) stop_server; echo "Stopped local Qwen AMD server" ;;
  restart) stop_server; start_server "${2:-}" ;;
  status) status_server ;;
  logs) tail -200 "${LOG_FILE}" ;;
  url) echo "${BASE_URL}/v1" ;;
  profiles) for p in $(profile_ids); do printf '%-34s %s\n' "$p" "$(profile_label "$p")"; done ;;
  -h|--help|help) usage ;;
  *) echo "unknown command: ${1}" >&2; usage >&2; exit 2 ;;
esac
