#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PI_LOCAL_QWEN_AMD_HOME:-${HOME}/.pi/local-qwen-amd}"
LLAMA_REPO="${PI_LOCAL_QWEN_AMD_LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"
LLAMA_REF="${PI_LOCAL_QWEN_AMD_LLAMA_REF:-master}"
MODEL_REPO="${PI_LOCAL_QWEN_AMD_MODEL_REPO:-unsloth/Qwen3.5-9B-MTP-GGUF}"
MODEL_FILE="${PI_LOCAL_QWEN_AMD_MODEL_FILE:-Qwen3.5-9B-Q4_K_M.gguf}"
BUILD_DIR="${PREFIX}/llama.cpp/build-vulkan"
MODEL_DIR="${PREFIX}/models/${MODEL_REPO}"
MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"
JOBS="${PI_LOCAL_QWEN_AMD_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

need() {
  command -v "$1" >/dev/null 2>&1 || missing+=("$1")
}

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

missing=()
need git
need curl
need cmake
need c++
if ! command -v glslc >/dev/null 2>&1 && ! command -v glslangValidator >/dev/null 2>&1; then
  missing+=("glslc-or-glslangValidator")
fi
if ((${#missing[@]})); then
  printf 'Missing: %s\n' "${missing[*]}" >&2
  print_dep_help >&2
  exit 1
fi

mkdir -p "${PREFIX}" "${MODEL_DIR}"

echo "==> Install prefix: ${PREFIX}"

if command -v vulkaninfo >/dev/null 2>&1; then
  echo "==> Vulkan devices:"
  vulkaninfo --summary 2>/dev/null | sed -n '/Devices:/,/^$/p' || true
else
  echo "==> vulkaninfo not found; build can continue, but install vulkan-tools to verify AMD GPU visibility."
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

if [[ ! -x "${BUILD_DIR}/bin/llama-server" ]]; then
  echo "llama-server build output missing: ${BUILD_DIR}/bin/llama-server" >&2
  exit 1
fi

if [[ ! -f "${MODEL_PATH}" ]]; then
  echo "==> Downloading ${MODEL_REPO}/${MODEL_FILE}"
  url="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}?download=true"
  curl -L --fail --continue-at - --retry 5 --retry-delay 5 -o "${MODEL_PATH}" "${url}"
else
  echo "==> Model already present: ${MODEL_PATH}"
fi

cat > "${PREFIX}/env" <<EOF
PI_LOCAL_QWEN_AMD_HOME=${PREFIX}
PI_LOCAL_QWEN_AMD_LLAMA_SERVER=${BUILD_DIR}/bin/llama-server
PI_LOCAL_QWEN_AMD_MODEL_PATH=${MODEL_PATH}
EOF

cat <<EOF

Install complete.

llama-server: ${BUILD_DIR}/bin/llama-server
model:        ${MODEL_PATH}

If you installed this as a pi package, select:
  local-qwen-amd/qwen35-9b-mtp-fast

Manual server control:
  PI_LOCAL_QWEN_AMD_HOME=${PREFIX} pi-local-qwen-amd-server start
  PI_LOCAL_QWEN_AMD_HOME=${PREFIX} pi-local-qwen-amd-server status
  PI_LOCAL_QWEN_AMD_HOME=${PREFIX} pi-local-qwen-amd-server stop
EOF
