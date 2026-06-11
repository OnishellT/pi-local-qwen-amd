# pi-local-qwen-amd

A generic [pi](https://pi.dev) package that registers a local OpenAI-compatible Qwen model and automatically manages a `llama.cpp` server on AMD/Vulkan systems.

Default model:

```text
local-qwen-amd/qwen35-9b-mtp-fast
```

Default endpoint:

```text
http://127.0.0.1:8004/v1
```

When you select the model in pi, the extension starts the server. When you switch away from the model or close pi, the extension stops the server.

## Requirements

- Linux machine with an AMD GPU visible through Vulkan
- pi installed
- Internet access
- Build tools: `git`, `curl`, `cmake`, C++ compiler, Vulkan headers/tools, shader compiler (`glslc` or `glslangValidator`)
- Enough disk for llama.cpp build + Qwen3.5-9B GGUF (~8-10 GB)
- Enough RAM/VRAM for Qwen3.5-9B Q4 at 64K context

The installer prints distro-specific package suggestions when dependencies are missing.

## Install

From this repo checkout:

```bash
pi install .
./scripts/install.sh
```

From git/npm package installs, run the installed bin if available:

```bash
pi-local-qwen-amd-install
```

The installer:

1. Creates `${PI_LOCAL_QWEN_AMD_HOME:-~/.pi/local-qwen-amd}`
2. Clones `ggml-org/llama.cpp`
3. Builds `llama-server` with Vulkan support
4. Downloads `unsloth/Qwen3.5-9B-MTP-GGUF/Qwen3.5-9B-Q4_K_M.gguf`

Then start pi from a trusted project and select:

```text
local-qwen-amd/qwen35-9b-mtp-fast
```

If the package is project-local, run `/trust` or start pi with `--approve` once so project extensions can load.

## Manual server controls

```bash
pi-local-qwen-amd-server start
pi-local-qwen-amd-server status
pi-local-qwen-amd-server logs
pi-local-qwen-amd-server stop
```

Or from inside pi:

```text
/local-qwen-amd status
/local-qwen-amd start
/local-qwen-amd stop
/local-qwen-amd install
```

## Defaults

The defaults are tuned for a Radeon RX 6800 XT class machine, but can be overridden with environment variables.

- Model: Qwen3.5-9B MTP Q4_K_M GGUF
- Context: 65,536 tokens for pi compatibility
- Device: `Vulkan1`
- MTP: `draft-mtp`, draft depth `3`
- Main KV: `f16`
- Draft KV: `q8_0`
- Batch/ubatch: `256/64`
- `SPEC_DRAFT_P_MIN=0.05`
- `KV_UNIFIED=false`
- Port: `8004`

## Configuration

Common environment overrides:

```bash
# Install/runtime location
export PI_LOCAL_QWEN_AMD_HOME="$HOME/.pi/local-qwen-amd"

# If your AMD discrete GPU is Vulkan0 instead of Vulkan1
export PI_LOCAL_QWEN_AMD_DEVICE=Vulkan0

# Port/provider endpoint
export PI_LOCAL_QWEN_AMD_PORT=8004

# Keep server running after pi exits/switches models
export PI_LOCAL_QWEN_AMD_KEEP_SERVER=1

# Context size
export PI_LOCAL_QWEN_AMD_CTX_SIZE=65536

# Use existing llama-server/model paths
export PI_LOCAL_QWEN_AMD_LLAMA_SERVER=/path/to/llama-server
export PI_LOCAL_QWEN_AMD_MODEL_PATH=/path/to/model.gguf
```

Installer overrides:

```bash
export PI_LOCAL_QWEN_AMD_LLAMA_REF=master
export PI_LOCAL_QWEN_AMD_MODEL_REPO=unsloth/Qwen3.5-9B-MTP-GGUF
export PI_LOCAL_QWEN_AMD_MODEL_FILE=Qwen3.5-9B-Q4_K_M.gguf
export PI_LOCAL_QWEN_AMD_BUILD_JOBS=12
```

## Testing

List model:

```bash
pi --list-models qwen35-9b
```

One-shot smoke test:

```bash
PI_SKIP_VERSION_CHECK=1 pi --model local-qwen-amd/qwen35-9b-mtp-fast -p 'Reply with exactly OK.'
```

Expected behavior:

- server starts before the provider request
- output is `OK`
- server stops after pi exits, unless `PI_LOCAL_QWEN_AMD_KEEP_SERVER=1`

## Notes

- This package does not require paths specific to any machine.
- It does not require an API key; the local OpenAI-compatible server ignores the placeholder key.
- If startup fails with the wrong Vulkan device, run `vulkaninfo --summary` and set `PI_LOCAL_QWEN_AMD_DEVICE` accordingly.
- The extension intentionally starts the server only when its model is selected, so normal pi usage with other models is unaffected.
