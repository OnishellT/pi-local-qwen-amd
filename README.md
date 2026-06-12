# pi-local-qwen-amd

A generic [pi](https://pi.dev) package that registers local OpenAI-compatible Qwen-family models and automatically manages a `llama.cpp` server on AMD/Vulkan systems.

Registered pi models:

```text
local-qwen-amd/qwen35-9b-mtp-fast
local-qwen-amd/qwopus35-9b-coder-mtp-q5-100k
```

Default endpoint:

```text
http://127.0.0.1:8004/v1
```

When you select either model in pi, the extension starts the correct `llama.cpp` server profile. When you switch away from these models or close pi, the extension stops the server.

## Models

| pi model | Hugging Face file | Purpose |
| --- | --- | --- |
| `local-qwen-amd/qwen35-9b-mtp-fast` | `unsloth/Qwen3.5-9B-MTP-GGUF/Qwen3.5-9B-Q4_K_M.gguf` | fastest general 9B MTP profile |
| `local-qwen-amd/qwopus35-9b-coder-mtp-q5-100k` | `Jackrong/Qwopus3.5-9B-Coder-MTP-GGUF/Qwopus3.5-9B-Coder-MTP-Q5_K_M.gguf` | agent/coding-tuned 100K Q5 quality-speed profile |

## Requirements

- Linux machine with an AMD GPU visible through Vulkan
- pi installed
- Internet access
- Build tools: `git`, `curl`, `cmake`, C++ compiler, Vulkan headers/tools, shader compiler (`glslc` or `glslangValidator`)
- Enough disk for llama.cpp build + selected model(s)
- Enough RAM/VRAM for the selected model/context

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

The installer asks which model to download:

1. Qwen3.5-9B MTP Q4_K_M fast
2. Qwopus3.5-9B Coder MTP Q5_K_M 100K
3. Both

Non-interactive examples:

```bash
pi-local-qwen-amd-install --model qwen
pi-local-qwen-amd-install --model qwopus
pi-local-qwen-amd-install --model both
```

The installer:

1. Creates `${PI_LOCAL_QWEN_AMD_HOME:-~/.pi/local-qwen-amd}`
2. Clones `ggml-org/llama.cpp`
3. Builds `llama-server` with Vulkan support
4. Downloads the selected GGUF model(s)

Then start pi from a trusted project and select either registered model. If the package is project-local, run `/trust` or start pi with `--approve` once so project extensions can load.

## Manual server controls

```bash
pi-local-qwen-amd-server profiles
pi-local-qwen-amd-server start qwen
pi-local-qwen-amd-server start qwopus
pi-local-qwen-amd-server status
pi-local-qwen-amd-server logs
pi-local-qwen-amd-server stop
```

Or from inside pi:

```text
/local-qwen-amd profiles
/local-qwen-amd start qwen
/local-qwen-amd start qwopus
/local-qwen-amd status
/local-qwen-amd stop
/local-qwen-amd install qwopus
```

## Defaults

The defaults are tuned for a Radeon RX 6800 XT class machine, but can be overridden with environment variables.

Common runtime defaults:

- Device: `Vulkan1`
- Main KV: `f16`
- Draft KV: `q8_0`
- `SPEC_DRAFT_P_MIN=0.05`
- `KV_UNIFIED=false`
- Port: `8004`

Qwen profile:

- Context: `65536`
- Quant: `Q4_K_M`
- MTP draft depth: `3`
- Batch/ubatch: `256/64`

Qwopus profile:

- Context: `100000`
- Quant: `Q5_K_M`
- MTP draft depth: `4`
- Batch/ubatch: `512/64`

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

# Runtime tuning overrides
export PI_LOCAL_QWEN_AMD_CTX_SIZE=65536
export PI_LOCAL_QWEN_AMD_BATCH_SIZE=512
export PI_LOCAL_QWEN_AMD_UBATCH_SIZE=64
export PI_LOCAL_QWEN_AMD_MTP_DRAFT_N=4

# Use existing llama-server or a custom single model path
export PI_LOCAL_QWEN_AMD_LLAMA_SERVER=/path/to/llama-server
export PI_LOCAL_QWEN_AMD_MODEL_PATH=/path/to/model.gguf
```

Installer overrides:

```bash
export PI_LOCAL_QWEN_AMD_LLAMA_REF=master
export PI_LOCAL_QWEN_AMD_BUILD_JOBS=12
export PI_LOCAL_QWEN_AMD_INSTALL_MODEL=both
```

## Testing

List models:

```bash
pi --list-models qwen
```

One-shot smoke tests:

```bash
PI_SKIP_VERSION_CHECK=1 pi --model local-qwen-amd/qwen35-9b-mtp-fast -p 'Reply with exactly OK.'
PI_SKIP_VERSION_CHECK=1 pi --model local-qwen-amd/qwopus35-9b-coder-mtp-q5-100k -p 'Reply with exactly OK.'
```

Expected behavior:

- server starts before the provider request
- output is `OK`
- server stops after pi exits, unless `PI_LOCAL_QWEN_AMD_KEEP_SERVER=1`

## Notes

- This package does not require paths specific to any machine.
- It does not require an API key; the local OpenAI-compatible server ignores the placeholder key.
- If startup fails with the wrong Vulkan device, run `vulkaninfo --summary` and set `PI_LOCAL_QWEN_AMD_DEVICE` accordingly.
- The extension intentionally starts the server only when one of its local models is selected, so normal pi usage with other models is unaffected.
