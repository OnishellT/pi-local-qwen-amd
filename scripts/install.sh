#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=profiles.sh
source "${SCRIPT_DIR}/profiles.sh"

PREFIX="${PI_LOCAL_QWEN_AMD_HOME:-${HOME}/.pi/local-qwen-amd}"
LLAMA_REPO="${PI_LOCAL_QWEN_AMD_LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"
LLAMA_REF="${PI_LOCAL_QWEN_AMD_LLAMA_REF:-master}"
BUILD_DIR="${PREFIX}/llama.cpp/build-vulkan"
JOBS="${PI_LOCAL_QWEN_AMD_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
INSTALL_MODEL="${PI_LOCAL_QWEN_AMD_INSTALL_MODEL:-}"

need() { command -v "$1" >/dev/null 2>&1 || missing+=("$1"); }

print_dep_help() {
  cat <<'EOF'
Missing required build/download tools.

Install examples:
  Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y git curl cmake build-essential vulkan-tools libvulkan-dev glslc
  Arch Linux:    sudo pacman -S --needed git curl cmake base-devel vulkan-tools vulkan-headers shaderc
  Fedora:        sudo dnf install -y git curl cmake gcc gcc-c++ make vulkan-tools vulkan-headers glslc

AMD GPU runtime examples:
  Debian/Ubuntu: sudo apt-get install -y mesa-vulkan-drivers
  Arch Linux:    sudo pacman -S --needed vulkan-radeon
  Fedora:        sudo dnf install -y mesa-vulkan-drivers
EOF
}

usage() {
  cat <<EOF
Usage: pi-local-qwen-amd-install [--model qwen|qwopus|both|PROFILE]

Profiles:
  qwen    qwen35-9b-mtp-fast              Qwen3.5-9B MTP Q4_K_M fast
  qwopus  qwopus35-9b-coder-mtp-q5-100k  Qwopus3.5-9B Coder MTP Q5_K_M 100K
  both    download both models

Environment:
  PI_LOCAL_QWEN_AMD_HOME          install prefix (default: ~/.pi/local-qwen-amd)
  PI_LOCAL_QWEN_AMD_INSTALL_MODEL qwen|qwopus|both|PROFILE
  PI_LOCAL_QWEN_AMD_LLAMA_REF     llama.cpp git ref (default: master)
  PI_LOCAL_QWEN_AMD_BUILD_JOBS    build jobs
EOF
}

normalize_choice() {
  case "$1" in
    qwen|qwen35-9b-mtp-fast) echo qwen35-9b-mtp-fast ;;
    qwopus|coder|qwopus35-9b-coder-mtp-q5-100k) echo qwopus35-9b-coder-mtp-q5-100k ;;
    both|all) echo both ;;
    *) return 1 ;;
  esac
}

while (($#)); do
  case "$1" in
    --model)
      [[ $# -ge 2 ]] || { echo "--model needs a value" >&2; exit 2; }
      INSTALL_MODEL="$2"; shift 2 ;;
    --model=*) INSTALL_MODEL="${1#--model=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "${INSTALL_MODEL}" ]]; then
  if [[ -t 0 ]]; then
    cat <<'EOF'
Choose model to install:
  1) Qwen3.5-9B MTP Q4_K_M fast (recommended fastest)
  2) Qwopus3.5-9B Coder MTP Q5_K_M 100K (recommended quality/speed for pi agents)
  3) Both
EOF
    read -r -p "Selection [2]: " choice
    case "${choice:-2}" in
      1) INSTALL_MODEL=qwen ;;
      2) INSTALL_MODEL=qwopus ;;
      3) INSTALL_MODEL=both ;;
      *) echo "invalid selection" >&2; exit 2 ;;
    esac
  else
    INSTALL_MODEL=qwopus
  fi
fi
INSTALL_MODEL="$(normalize_choice "${INSTALL_MODEL}")" || { echo "unknown model choice: ${INSTALL_MODEL}" >&2; usage >&2; exit 2; }

missing=()
need git; need curl; need cmake; need c++
if ! command -v glslc >/dev/null 2>&1 && ! command -v glslangValidator >/dev/null 2>&1; then missing+=("glslc-or-glslangValidator"); fi
if ((${#missing[@]})); then printf 'Missing: %s\n' "${missing[*]}" >&2; print_dep_help >&2; exit 1; fi

mkdir -p "${PREFIX}"
echo "==> Install prefix: ${PREFIX}"

if command -v vulkaninfo >/dev/null 2>&1; then
  echo "==> Vulkan devices:"
  vulkaninfo --summary 2>/dev/null | sed -n '/Devices:/,/^$/p' || true
else
  echo "==> vulkaninfo not found; install vulkan-tools to verify AMD GPU visibility."
fi

if [[ ! -d "${PREFIX}/llama.cpp/.git" ]]; then
  echo "==> Cloning llama.cpp from ${LLAMA_REPO}"
  git clone "${LLAMA_REPO}" "${PREFIX}/llama.cpp"
fi

cd "${PREFIX}/llama.cpp"
echo "==> Updating llama.cpp (${LLAMA_REF})"
git fetch --tags origin
git checkout "${LLAMA_REF}"
git pull --ff-only origin "${LLAMA_REF}" || true

echo "==> Configuring llama.cpp Vulkan build"
cmake -S . -B "${BUILD_DIR}" -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release

echo "==> Building llama-server with ${JOBS} jobs"
cmake --build "${BUILD_DIR}" --target llama-server -j "${JOBS}"
[[ -x "${BUILD_DIR}/bin/llama-server" ]] || { echo "llama-server missing: ${BUILD_DIR}/bin/llama-server" >&2; exit 1; }

download_profile() {
  local profile="$1" repo file dir path url
  repo="$(profile_repo "$profile")"; file="$(profile_file "$profile")"
  dir="${PREFIX}/models/${repo}"; path="${dir}/${file}"
  mkdir -p "${dir}"
  if [[ ! -f "${path}" ]]; then
    echo "==> Downloading ${repo}/${file}"
    url="https://huggingface.co/${repo}/resolve/main/${file}?download=true"
    curl -L --fail --continue-at - --retry 5 --retry-delay 5 -o "${path}" "${url}"
  else
    echo "==> Model already present: ${path}"
  fi
}

case "${INSTALL_MODEL}" in
  both) for p in $(profile_ids); do download_profile "$p"; done; DEFAULT_PROFILE=qwopus35-9b-coder-mtp-q5-100k ;;
  *) download_profile "${INSTALL_MODEL}"; DEFAULT_PROFILE="${INSTALL_MODEL}" ;;
esac

cat > "${PREFIX}/env" <<EOF
PI_LOCAL_QWEN_AMD_HOME=${PREFIX}
PI_LOCAL_QWEN_AMD_LLAMA_SERVER=${BUILD_DIR}/bin/llama-server
PI_LOCAL_QWEN_AMD_DEFAULT_MODEL=${DEFAULT_PROFILE}
EOF

cat <<EOF

Install complete.

llama-server: ${BUILD_DIR}/bin/llama-server
default model: ${DEFAULT_PROFILE} ($(profile_label "${DEFAULT_PROFILE}"))

Available pi models:
  local-qwen-amd/qwen35-9b-mtp-fast
  local-qwen-amd/qwopus35-9b-coder-mtp-q5-100k

Manual server control:
  PI_LOCAL_QWEN_AMD_HOME=${PREFIX} pi-local-qwen-amd-server start ${DEFAULT_PROFILE}
  PI_LOCAL_QWEN_AMD_HOME=${PREFIX} pi-local-qwen-amd-server status
  PI_LOCAL_QWEN_AMD_HOME=${PREFIX} pi-local-qwen-amd-server stop
EOF
