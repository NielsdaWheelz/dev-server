#!/bin/sh

# One account's MCP credential; no credential output or cross-profile inheritance.
jarvis_memory_profile_env() {
  [ "$#" -eq 2 ] || return 64
  unset JARVIS_MEMORY_CODEX_PERSONAL_BEARER JARVIS_MEMORY_CODEX_WORK_BEARER \
    JARVIS_MEMORY_CODEX_WORK2_BEARER JARVIS_MEMORY_CLAUDE_PERSONAL_BEARER \
    JARVIS_MEMORY_CLAUDE_WORK_BEARER
  case "$2" in
  codex-personal) _jarvis_memory_variable=JARVIS_MEMORY_CODEX_PERSONAL_BEARER ;;
  codex-work) _jarvis_memory_variable=JARVIS_MEMORY_CODEX_WORK_BEARER ;;
  codex-work2) _jarvis_memory_variable=JARVIS_MEMORY_CODEX_WORK2_BEARER ;;
  claude-personal) _jarvis_memory_variable=JARVIS_MEMORY_CLAUDE_PERSONAL_BEARER ;;
  claude-work) _jarvis_memory_variable=JARVIS_MEMORY_CLAUDE_WORK_BEARER ;;
  '') return 0 ;;
  *) return 64 ;;
  esac
  if [ -f "$1/.config/jarvis-memory/clients.env" ]; then
    while IFS='=' read -r _jarvis_memory_name _jarvis_memory_token; do
      [ "$_jarvis_memory_name" = "export $_jarvis_memory_variable" ] || continue
      export "$_jarvis_memory_variable=$_jarvis_memory_token"
      break
    done <"$1/.config/jarvis-memory/clients.env"
  fi
  unset _jarvis_memory_variable _jarvis_memory_name _jarvis_memory_token
}
