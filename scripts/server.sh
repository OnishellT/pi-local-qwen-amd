#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PI_LOCAL_QWEN_AMD_HOME:-${HOME}/.pi/local-qwen-amd}"
HOST="${PI_LOCAL_QWEN_AMD_HOST:-127.0.0.1}"
PORT="${PI_LOCAL_QWEN_AMD_PORT:-8004}"
BASE_URL="http://${HOST}:${PORT}"
MODEL_ID="${PI_LOCAL_QWEN_AMD_MODEL_ID:-qwen35-9b-mtp-fast}"
LLAMA_SERVER="${PI_LOCAL_QWEN_AMD_LLAMA_SERVER:-${PREFIX}/llama.cpp/build-vulkan/bin/llama-server}"
MODEL_PATH="${PI_LOCAL_QWEN_AMD_MODEL_PATH:-${PREFIX}/models/unsloth/Qwen3.5-9B-MTP-GGUF/Qwen3.5-9B-Q4_K_M.gguf}"
STATE_DIR="${PREFIX}/run"
LOG_DIR="${PREFIX}/logs"
PID_FILE="${STATE_DIR}/server.pid"
STATE_FILE="${STATE_DIR}/server.env"
LOG_FILE="${LOG_DIR}/server.log"
STARTUP_TIMEOUT="${PI_LOCAL_QWEN_AMD_STARTUP_TIMEOUT:-120}"

# Pi prompts are larger than simple llama.cpp smoke tests. 64K is the safe default.
CTX_SIZE="${PI_LOCAL_QWEN_AMD_CTX_SIZE:-65536}"
FIT_CTX="${PI_LOCAL_QWEN_AMD_FIT_CTX:-${CTX_SIZE}}"
DEVICE="${PI_LOCAL_QWEN_AMD_DEVICE:-Vulkan1}"
THREADS="${PI_LOCAL_QWEN_AMD_THREADS:-12}"
THREADS_BATCH="${PI_LOCAL_QWEN_AMD_THREADS_BATCH:-24}"
BATCH_SIZE="${PI_LOCAL_QWEN_AMD_BATCH_SIZE:-256}"
UBATCH_SIZE="${PI_LOCAL_QWEN_AMD_UBATCH_SIZE:-64}"
MTP_DRAFT_N="${PI_LOCAL_QWEN_AMD_MTP_DRAFT_N:-3}"
SPEC_DRAFT_P_MIN="${PI_LOCAL_QWEN_AMD_SPEC_DRAFT_P_MIN:-0.05}"
CACHE_TYPE_K="${PI_LOCAL_QWEN_AMD_CACHE_TYPE_K:-f16}"
CACHE_TYPE_V="${PI_LOCAL_QWEN_AMD_CACHE_TYPE_V:-f16}"
SPEC_DRAFT_TYPE_K="${PI_LOCAL_QWEN_AMD_SPEC_DRAFT_TYPE_K:-q8_0}"
SPEC_DRAFT_TYPE_V="${PI_LOCAL_QWEN_AMD_SPEC_DRAFT_TYPE_V:-q8_0}"
NO_MMAP="${PI_LOCAL_QWEN_AMD_NO_MMAP:-true}"
KV_UNIFIED="${PI_LOCAL_QWEN_AMD_KV_UNIFIED:-false}"

mkdir -p "${STATE_DIR}" "${LOG_DIR}"

usage() {
  cat <<EOF
Usage: pi-local-qwen-amd-server <start|stop|restart|status|logs|url>

Environment overrides:
  PI_LOCAL_QWEN_AMD_HOME          install prefix (default: ~/.pi/local-qwen-amd)
  PI_LOCAL_QWEN_AMD_PORT          server port (default: 8004)
  PI_LOCAL_QWEN_AMD_DEVICE        Vulkan device (default: Vulkan1; set Vulkan0 if your AMD dGPU is first)
  PI_LOCAL_QWEN_AMD_CTX_SIZE      context size for pi (default: 65536)
  PI_LOCAL_QWEN_AMD_KEEP_SERVER=1 extension leaves server running on shutdown/model change
EOF
}

healthy() {
  curl -fsS --max-time 2 "${BASE_URL}/health" >/dev/null 2>&1
}

pid_running() {
  [[ -f "${PID_FILE}" ]] || return 1
  local pid
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null
}

port_pid() {
  pgrep -af llama-server 2>/dev/null | grep -F -- "--port ${PORT}" | awk '{print $1}' | head -1 || true
}

start_server() {
  if healthy; then
    echo "Already healthy: ${BASE_URL}/v1"
    return 0
  fi
  if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "llama-server not found: ${LLAMA_SERVER}" >&2
    echo "Run: pi-local-qwen-amd-install" >&2
    return 1
  fi
  if [[ ! -f "${MODEL_PATH}" ]]; then
    echo "model not found: ${MODEL_PATH}" >&2
    echo "Run: pi-local-qwen-amd-install" >&2
    return 1
  fi

  stop_server >/dev/null 2>&1 || true
  : > "${LOG_FILE}"

  args=(
    --model "${MODEL_PATH}"
    --alias "${MODEL_ID}"
    --host "${HOST}"
    --port "${PORT}"
    --ctx-size "${CTX_SIZE}"
    --parallel 1
    --threads "${THREADS}"
    --threads-batch "${THREADS_BATCH}"
    --batch-size "${BATCH_SIZE}"
    --ubatch-size "${UBATCH_SIZE}"
    --device "${DEVICE}"
    --fit on
    --fit-target 1024
    --fit-ctx "${FIT_CTX}"
    --flash-attn on
    --cache-type-k "${CACHE_TYPE_K}"
    --cache-type-v "${CACHE_TYPE_V}"
    --spec-type draft-mtp
    --spec-draft-n-max "${MTP_DRAFT_N}"
    --spec-draft-p-min "${SPEC_DRAFT_P_MIN}"
    --spec-draft-p-split 0.10
    --spec-draft-type-k "${SPEC_DRAFT_TYPE_K}"
    --spec-draft-type-v "${SPEC_DRAFT_TYPE_V}"
    --spec-ngram-mod-n-match 24
    --spec-ngram-mod-n-min 48
    --spec-ngram-mod-n-max 64
    --temp 0.6
    --top-p 0.95
    --top-k 20
    --min-p 0.0
    --presence-penalty 0.0
    --repeat-penalty 1.0
    --jinja
    --reasoning on
    --cont-batching
    --cache-prompt
    --metrics
  )
  if [[ "${NO_MMAP}" == "true" || "${NO_MMAP}" == "1" || "${NO_MMAP}" == "on" ]]; then
    args+=(--no-mmap)
  fi
  if [[ "${KV_UNIFIED}" == "true" || "${KV_UNIFIED}" == "1" || "${KV_UNIFIED}" == "on" ]]; then
    args+=(--kv-unified)
  fi

  nohup "${LLAMA_SERVER}" "${args[@]}" >>"${LOG_FILE}" 2>&1 &
  echo $! > "${PID_FILE}"

  for ((i=0; i<STARTUP_TIMEOUT; i++)); do
    if healthy; then
      cat > "${STATE_FILE}" <<EOF
model=${MODEL_ID}
base_url=${BASE_URL}/v1
pid=$(cat "${PID_FILE}")
log=${LOG_FILE}
model_path=${MODEL_PATH}
llama_server=${LLAMA_SERVER}
ctx_size=${CTX_SIZE}
device=${DEVICE}
EOF
      echo "Started ${MODEL_ID}: ${BASE_URL}/v1"
      echo "Log: ${LOG_FILE}"
      return 0
    fi
    if ! pid_running; then
      echo "llama-server exited during startup" >&2
      tail -120 "${LOG_FILE}" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "server did not become healthy: ${BASE_URL}/health" >&2
  echo "Log: ${LOG_FILE}" >&2
  return 1
}

stop_server() {
  if pid_running; then
    kill -TERM "$(cat "${PID_FILE}")" 2>/dev/null || true
  fi
  local pid
  pid="$(port_pid)"
  if [[ -n "${pid}" ]]; then
    kill -TERM "${pid}" 2>/dev/null || true
  fi
  for _ in {1..40}; do
    pid_running || [[ -z "$(port_pid)" ]] && break
    sleep 0.25
  done
  if pid_running; then kill -KILL "$(cat "${PID_FILE}")" 2>/dev/null || true; fi
  pid="$(port_pid)"
  if [[ -n "${pid}" ]]; then kill -KILL "${pid}" 2>/dev/null || true; fi
  rm -f "${PID_FILE}" "${STATE_FILE}"
}

status_server() {
  if healthy; then echo "healthy: ${BASE_URL}/v1"; else echo "not healthy: ${BASE_URL}/v1"; fi
  [[ -f "${STATE_FILE}" ]] && cat "${STATE_FILE}"
}

case "${1:-status}" in
  start) start_server ;;
  stop) stop_server; echo "Stopped ${MODEL_ID}" ;;
  restart) stop_server; start_server ;;
  status) status_server ;;
  logs) tail -200 "${LOG_FILE}" ;;
  url) echo "${BASE_URL}/v1" ;;
  -h|--help|help) usage ;;
  *) echo "unknown command: ${1}" >&2; usage >&2; exit 2 ;;
esac
