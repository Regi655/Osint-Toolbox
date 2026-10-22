#!/usr/bin/env bash
#
# osint-launcher.sh — interactive menu + batch dispatcher for osint-toolbox.
#
# Runs INSIDE the Docker image, where the tools are on PATH. Two modes:
#   - interactive menu: pick a tool, type a target, see results
#   - batch:            `docker run ... osint-toolbox batch --targets ... --outdir ...`
#
# See README.md for the authorized-use disclaimer.

set -u

# ── Batch mode ───────────────────────────────────────────────────────────────
# If the first argument is "batch", skip the menu and hand everything to the
# Python batch runner. This is what lets you run the container headless.
if [[ "${1:-}" == "batch" ]]; then
  shift
  exec python3 /opt/osint/osint-batch.py "$@"
fi

# ── Colors ───────────────────────────────────────────────────────────────────
C_RESET=$'\e[0m'; C_TITLE=$'\e[1;36m'; C_ITEM=$'\e[0;37m'
C_OK=$'\e[0;32m'; C_NO=$'\e[0;31m'; C_WARN=$'\e[0;33m'; C_PROMPT=$'\e[1;35m'

# ── Tool definitions ─────────────────────────────────────────────────────────
# Parallel arrays (same index = same tool):
#   NAME = label shown in the menu
#   CMD  = command to run (all three are on PATH inside the image)
#   KIND = input type: "email" | "user" | "both"
NAME=(); CMD=(); KIND=()
add_tool() { NAME+=("$1"); CMD+=("$2"); KIND+=("$3"); }

#        menu label      command         input type
add_tool "mosint"        "mosint"        "email"
add_tool "gosearch"      "gosearch"      "user"
add_tool "user-scanner"  "user-scanner"  "both"

# ── Helpers ──────────────────────────────────────────────────────────────────
tool_ok() { command -v "${CMD[$1]}" >/dev/null 2>&1; }

print_menu() {
  clear
  echo "${C_TITLE}╔════════════════════════════════════════════════╗${C_RESET}"
  echo "${C_TITLE}║              osint-toolbox — menu               ║${C_RESET}"
  echo "${C_TITLE}╚════════════════════════════════════════════════╝${C_RESET}"
  echo
  local i
  for i in "${!NAME[@]}"; do
    local n=$((i + 1)) status
    if tool_ok "$i"; then status="${C_OK}●${C_RESET}"; else status="${C_NO}○${C_RESET}"; fi
    printf "   %s  ${C_ITEM}%2d)${C_RESET} %s\n" "$status" "$n" "${NAME[$i]}"
  done
  echo
  echo "   ${C_ITEM} b)${C_RESET} batch from a list file  → Markdown report"
  echo "   ${C_ITEM} q)${C_RESET} quit"
  echo
}

# ── Interactive batch: ask for list file + output dir, then run the Python ────
run_batch() {
  local tf out
  printf "%sList file (default /opt/osint/targets.txt): %s" "$C_PROMPT" "$C_RESET"
  read -r tf; tf="${tf:-/opt/osint/targets.txt}"
  printf "%sOutput directory (default /opt/osint/out): %s" "$C_PROMPT" "$C_RESET"
  read -r out; out="${out:-/opt/osint/out}"
  if [[ ! -f "$tf" ]]; then
    echo "${C_NO}File not found: $tf${C_RESET}"
    echo "${C_WARN}Mount it from the host, e.g.  -v \$HOME/targets.txt:/opt/osint/targets.txt:ro${C_RESET}"
    return
  fi
  mkdir -p "$out"
  python3 /opt/osint/osint-batch.py --targets "$tf" --outdir "$out"
}

# ── Run one tool against one target ──────────────────────────────────────────
run_tool() {
  local i="$1"
  local name="${NAME[$i]}" cmd="${CMD[$i]}" kind="${KIND[$i]}"

  if ! tool_ok "$i"; then
    echo; echo "${C_NO}'$name' is not available in this image.${C_RESET}"
    return
  fi

  local target mode
  case "$kind" in
    user)
      printf "%sUsername: %s" "$C_PROMPT" "$C_RESET"; read -r target
      [[ -z "$target" ]] && { echo "Cancelled."; return; }
      # 'set -x' echoes the exact command before running it, so you can see it.
      set -x; "$cmd" -u "$target"; set +x ;;
    email)
      printf "%sEmail: %s" "$C_PROMPT" "$C_RESET"; read -r target
      [[ -z "$target" ]] && { echo "Cancelled."; return; }
      # mosint takes the email as a positional argument, with no flag.
      set -x; "$cmd" "$target"; set +x ;;
    both)
      printf "%sSearch by (u)sername or (e)mail? [u/e]: %s" "$C_PROMPT" "$C_RESET"; read -r mode
      printf "%sValue: %s" "$C_PROMPT" "$C_RESET"; read -r target
      [[ -z "$target" ]] && { echo "Cancelled."; return; }
      if [[ "$mode" == [eE] ]]; then set -x; "$cmd" -e "$target"; set +x
      else set -x; "$cmd" -u "$target"; set +x; fi ;;
  esac
}

# ── Main loop ────────────────────────────────────────────────────────────────
main() {
  while true; do
    print_menu
    printf "%sChoose a number (or q to quit): %s" "$C_PROMPT" "$C_RESET"
    read -r choice || exit 0        # Ctrl-D exits cleanly
    [[ "$choice" == [qQ] ]] && { echo "Bye!"; exit 0; }
    if [[ "$choice" == [bB] ]]; then
      run_batch
      echo; printf "%sPress Enter to return to the menu...%s" "$C_ITEM" "$C_RESET"; read -r _
      continue
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#NAME[@]} )); then
      echo "${C_NO}Invalid choice.${C_RESET}"; sleep 1; continue
    fi
    run_tool $((choice - 1))
    echo
    printf "%sPress Enter to return to the menu...%s" "$C_ITEM" "$C_RESET"
    read -r _
  done
}

main
