#!/usr/bin/env bash
# Shared model profiles for pi-local-qwen-amd. Source this file; do not execute directly.

profile_ids() {
  printf '%s\n' qwen35-9b-mtp-fast qwopus35-9b-coder-mtp-q5-100k
}

profile_label() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "Qwen3.5-9B MTP Q4_K_M fast" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "Qwopus3.5-9B Coder MTP Q5_K_M 100K" ;;
    *) return 1 ;;
  esac
}

profile_repo() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "unsloth/Qwen3.5-9B-MTP-GGUF" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "Jackrong/Qwopus3.5-9B-Coder-MTP-GGUF" ;;
    *) return 1 ;;
  esac
}

profile_file() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "Qwen3.5-9B-Q4_K_M.gguf" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "Qwopus3.5-9B-Coder-MTP-Q5_K_M.gguf" ;;
    *) return 1 ;;
  esac
}

profile_ctx() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "65536" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "100000" ;;
    *) return 1 ;;
  esac
}

profile_max_tokens() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "8192" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "8192" ;;
    *) return 1 ;;
  esac
}

profile_batch() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "256" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "512" ;;
    *) return 1 ;;
  esac
}

profile_ubatch() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "64" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "64" ;;
    *) return 1 ;;
  esac
}

profile_mtp_draft_n() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "3" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "4" ;;
    *) return 1 ;;
  esac
}

profile_spec_p_min() {
  case "$1" in
    qwen35-9b-mtp-fast) echo "0.05" ;;
    qwopus35-9b-coder-mtp-q5-100k) echo "0.05" ;;
    *) return 1 ;;
  esac
}

profile_model_path() {
  local prefix="$1" profile="$2"
  printf '%s/models/%s/%s\n' "$prefix" "$(profile_repo "$profile")" "$(profile_file "$profile")"
}

profile_exists() {
  local profile="$1"
  profile_label "$profile" >/dev/null 2>&1
}
