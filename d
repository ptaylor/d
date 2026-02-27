#!/usr/bin/env bash
# d - Docker utility script
# Makes common docker operations fast by matching containers by name pattern.
#
# Single-match commands (logs, shell, exec, inspect, env):
#   If multiple containers match, shows an interactive selector.
# Multi-match commands (kill, stop, rm, restart):
#   Operates on ALL containers matching the pattern.

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors — use $'...' so bash stores actual ESC characters, not literals.
# Suppressed when stdout is not a tty or when NO_COLOR is set.
# ---------------------------------------------------------------------------
if [[ -t 1 && -t 2 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
${BOLD}d${NC} — Docker container utility

${BOLD}USAGE${NC}
  d <command> [pattern] [args...]

${BOLD}COMMANDS${NC}
  ${CYAN}ps${NC}     [pattern]           List running containers (filtered if pattern given)
  ${CYAN}psa${NC}    [pattern]           List all containers including stopped
  ${CYAN}logs${NC}   <pattern>           Follow logs of matched container  ${DIM}(single-select)${NC}
  ${CYAN}shell${NC}  <pattern>           Open shell in matched container   ${DIM}(single-select)${NC}
  ${CYAN}exec${NC}   <pattern> <cmd...>  Run command in matched container  ${DIM}(single-select)${NC}
  ${CYAN}env${NC}    <pattern>           Show environment variables        ${DIM}(single-select)${NC}
  ${CYAN}inspect${NC} <pattern>          Inspect matched container         ${DIM}(single-select)${NC}
  ${CYAN}stop${NC}   <pattern>           Stop all matching containers
  ${CYAN}kill${NC}   <pattern>           Kill all matching containers
  ${CYAN}rm${NC}     <pattern>           Remove all matching containers (force)
  ${CYAN}restart${NC} <pattern>          Restart all matching containers
  ${CYAN}stats${NC}  [pattern]           Live resource stats (filtered if pattern given)

${BOLD}PATTERN${NC}
  Case-insensitive substring match against container name and image name.

${BOLD}SELECTION${NC}
  When multiple containers match a single-select command, an interactive
  menu is shown. Use ${BOLD}↑/↓${NC} arrows and ${BOLD}Enter${NC} to choose.
  Requires ${BOLD}fzf${NC} if installed (recommended), otherwise uses built-in selector.

${BOLD}EXAMPLES${NC}
  d logs api             # tail logs for container whose name contains "api"
  d shell postgres       # open shell in the postgres container
  d exec worker env      # run 'env' in the worker container
  d kill feature-branch  # kill all containers matching "feature-branch"
  d stop redis           # stop all containers matching "redis"
  d ps                   # list all running containers
  d ps web               # list running containers matching "web"
EOF
}

# ---------------------------------------------------------------------------
# Container discovery
# ---------------------------------------------------------------------------

# List running containers, optionally filtered by pattern.
# Output: tab-separated  ID  NAME  IMAGE  STATUS
_list_running() {
    local pattern="${1:-}"
    local out
    out=$(docker ps --format "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null) || {
        echo -e "${RED}error:${NC} docker is not running or not accessible." >&2
        exit 1
    }
    if [[ -n "$pattern" ]]; then
        echo "$out" | grep -i "$pattern" || true
    else
        echo "$out"
    fi
}

# List all containers (including stopped), optionally filtered.
_list_all() {
    local pattern="${1:-}"
    local out
    out=$(docker ps -a --format "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null) || {
        echo -e "${RED}error:${NC} docker is not running or not accessible." >&2
        exit 1
    }
    if [[ -n "$pattern" ]]; then
        echo "$out" | grep -i "$pattern" || true
    else
        echo "$out"
    fi
}

# Require at least one match from running containers; exit on none.
_require_matches() {
    local pattern="$1"
    local matches="$2"
    if [[ -z "$matches" ]]; then
        echo -e "${RED}error:${NC} No running containers match pattern: ${BOLD}${pattern}${NC}" >&2
        echo -e "       Run ${CYAN}d ps${NC} to see running containers." >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Interactive single-container selector
# ---------------------------------------------------------------------------

# Built-in arrow-key menu.  Prints selected line to stdout.
_arrow_select() {
    local items_str="$1"
    local prompt="${2:-Select a container}"

    # Parse lines into array
    local -a lines=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && lines+=("$line")
    done <<< "$items_str"

    local count=${#lines[@]}
    local selected=0

    # Draw menu from current cursor position.
    # Each line starts with \033[2K (erase line) so redraws are clean.
    # Items 0-8 (displayed as 1-9) get a number key shortcut.
    _print_menu() {
        local i name image status numkey
        for (( i=0; i<count; i++ )); do
            name=$(  awk -F'\t' '{print $2}' <<< "${lines[$i]}")
            image=$( awk -F'\t' '{print $3}' <<< "${lines[$i]}")
            status=$(awk -F'\t' '{print $4}' <<< "${lines[$i]}")
            # Show digit for first 9 items, blank space for the rest
            if (( i < 9 )); then
                numkey="${CYAN}$((i+1))${NC}"
            else
                numkey=" "
            fi
            if (( i == selected )); then
                printf '\033[2K '"${numkey} ${GREEN}"'▶ %-30s'"${NC}  ${DIM}"'%-35s  %s'"${NC}"'\n' \
                    "$name" "$image" "$status" >&2
            else
                printf '\033[2K '"${numkey}"'   %-30s  '"${DIM}"'%-35s  %s'"${NC}"'\n' \
                    "$name" "$image" "$status" >&2
            fi
        done
    }

    # Hide cursor while drawing
    printf '\033[?25l' >&2

    printf "${BOLD}%s${NC} (↑/↓ or 1-9 to select, Enter to confirm, q to quit):\n" \
        "$prompt" >&2

    # Save cursor position immediately before the menu rows.
    # \033[s saves; \033[u restores — works in iTerm2, Terminal.app, xterm.
    printf '\033[s' >&2
    _print_menu

    local key
    while true; do
        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\x1b')
                IFS= read -rsn1 -t 1 key </dev/tty || true
                if [[ "$key" == '[' ]]; then
                    IFS= read -rsn1 -t 1 key </dev/tty || true
                    case "$key" in
                        A) (( selected > 0        )) && (( selected-- )) ;;
                        B) (( selected < count-1  )) && (( selected++ )) ;;
                    esac
                fi
                ;;
            [1-9])
                local idx=$(( key - 1 ))
                if (( idx < count )); then
                    selected=$idx
                    # Immediate selection — redraw to highlight chosen row, then exit
                    printf '\033[u' >&2
                    _print_menu
                    break
                fi
                ;;
            '') # Enter
                break
                ;;
            q|Q)
                # Restore, clear to end of screen, show cursor, print message
                printf '\033[u\033[J\033[?25h' >&2
                exit 0
                ;;
        esac

        # Restore cursor to top of menu and redraw in place
        printf '\033[u' >&2
        _print_menu
    done

    # Move past the menu, show cursor
    printf '\033[u\033[J\033[?25h' >&2

    # Store result in global — avoids subshell so exit 0 above reaches the script
    _SELECT_RESULT="${lines[$selected]}"
}

# Select exactly one container from matches.
# If only one match, returns it directly.
# If multiple, prompts interactively.
# Prints the selected raw line to stdout.
# Global used by _select_one / _arrow_select to avoid subshell exit-trap issues.
_SELECT_RESULT=''

_select_one() {
    local pattern="$1"
    local matches="$2"

    local count
    count=$(echo "$matches" | grep -c . || echo 0)

    if (( count == 1 )); then
        _SELECT_RESULT="$matches"
        return
    fi

    # Multiple matches — need interactive selection
    if command -v fzf &>/dev/null; then
        local selected
        selected=$(
            echo "$matches" \
            | fzf \
                --height=40% \
                --reverse \
                --prompt="Select container > " \
                --delimiter=$'\t' \
                --with-nth='2,3,4' \
                --header="NAME                            IMAGE                               STATUS" \
                --header-first \
                --no-multi \
                --ansi \
                2>/dev/tty
        ) || exit 0   # fzf cancelled — exit cleanly
        _SELECT_RESULT="$selected"
    else
        _arrow_select "$matches" "Multiple containers match '${pattern}'"
        # _SELECT_RESULT set by _arrow_select (or script exited on cancel)
    fi
}

# Extract container ID from a raw match line (first tab-delimited field).
_id_of() {
    awk -F'\t' '{print $1}' <<< "$1"
}

# Extract container name from a raw match line (second tab-delimited field).
_name_of() {
    awk -F'\t' '{print $2}' <<< "$1"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_ps() {
    local pattern="${1:-}"
    if [[ -n "$pattern" ]]; then
        docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" \
            | { IFS= read -r header; echo "$header"; grep -i "$pattern" || true; }
    else
        docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    fi
}

cmd_psa() {
    local pattern="${1:-}"
    if [[ -n "$pattern" ]]; then
        docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" \
            | { IFS= read -r header; echo "$header"; grep -i "$pattern" || true; }
    else
        docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    fi
}

cmd_logs() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }

    local matches
    matches=$(_list_running "$pattern")
    _require_matches "$pattern" "$matches"

    local line id name
    _select_one "$pattern" "$matches"; line="$_SELECT_RESULT"
    id=$(_id_of "$line")
    name=$(_name_of "$line")

    echo -e "${CYAN}→${NC} Logs for ${BOLD}${name}${NC} (${DIM}${id}${NC})" >&2
    exec docker logs -f "$id"
}

cmd_shell() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }

    local matches
    matches=$(_list_running "$pattern")
    _require_matches "$pattern" "$matches"

    local line id name
    _select_one "$pattern" "$matches"; line="$_SELECT_RESULT"
    id=$(_id_of "$line")
    name=$(_name_of "$line")

    echo -e "${CYAN}→${NC} Shell in ${BOLD}${name}${NC} (${DIM}${id}${NC})" >&2
    docker exec -it "$id" bash 2>/dev/null \
        || docker exec -it "$id" sh 2>/dev/null \
        || { echo -e "${RED}error:${NC} Could not start bash or sh in container." >&2; exit 1; }
}

cmd_exec() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }
    shift
    [[ $# -eq 0 ]] && { echo -e "${RED}error:${NC} command required after pattern" >&2; exit 1; }

    local matches
    matches=$(_list_running "$pattern")
    _require_matches "$pattern" "$matches"

    local line id name
    _select_one "$pattern" "$matches"; line="$_SELECT_RESULT"
    id=$(_id_of "$line")
    name=$(_name_of "$line")

    echo -e "${CYAN}→${NC} Exec in ${BOLD}${name}${NC} (${DIM}${id}${NC}): $*" >&2
    exec docker exec -it "$id" "$@"
}

cmd_env() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }

    local matches
    matches=$(_list_running "$pattern")
    _require_matches "$pattern" "$matches"

    local line id name
    _select_one "$pattern" "$matches"; line="$_SELECT_RESULT"
    id=$(_id_of "$line")
    name=$(_name_of "$line")

    echo -e "${CYAN}→${NC} Environment for ${BOLD}${name}${NC} (${DIM}${id}${NC}):" >&2
    docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id" | sort
}

cmd_inspect() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }

    local matches
    matches=$(_list_running "$pattern")
    _require_matches "$pattern" "$matches"

    local line id name
    _select_one "$pattern" "$matches"; line="$_SELECT_RESULT"
    id=$(_id_of "$line")
    name=$(_name_of "$line")

    echo -e "${CYAN}→${NC} Inspecting ${BOLD}${name}${NC} (${DIM}${id}${NC})" >&2
    docker inspect "$id"
}

# Multi-match commands — operate on ALL containers matching pattern.

_run_on_all() {
    local action="$1"       # verb for display (e.g. "Stopping")
    local docker_cmd="$2"   # docker sub-command (e.g. "stop")
    local pattern="$3"
    shift 3
    local extra_args=("$@")

    local matches
    matches=$(_list_running "$pattern")
    _require_matches "$pattern" "$matches"

    local count
    count=$(echo "$matches" | grep -c .)

    echo -e "${CYAN}→${NC} ${action} ${BOLD}${count}${NC} container(s) matching ${BOLD}${pattern}${NC}:" >&2

    local id name
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        id=$(_id_of "$line")
        name=$(_name_of "$line")
        printf "  %-30s  %s\n" "$name" "$id" >&2
        docker "$docker_cmd" "${extra_args[@]+"${extra_args[@]}"}" "$id"
    done <<< "$matches"
}

cmd_stop() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }
    _run_on_all "Stopping" "stop" "$pattern"
}

cmd_kill() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }
    _run_on_all "Killing" "kill" "$pattern"
}

cmd_restart() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }
    _run_on_all "Restarting" "restart" "$pattern"
}

cmd_rm() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { echo -e "${RED}error:${NC} pattern required" >&2; usage; exit 1; }

    # rm can target stopped containers too, so use _list_all
    local matches
    matches=$(_list_all "$pattern")
    if [[ -z "$matches" ]]; then
        echo -e "${RED}error:${NC} No containers (running or stopped) match pattern: ${BOLD}${pattern}${NC}" >&2
        exit 1
    fi

    local count
    count=$(echo "$matches" | grep -c .)
    echo -e "${CYAN}→${NC} Force-removing ${BOLD}${count}${NC} container(s) matching ${BOLD}${pattern}${NC}:" >&2

    local id name
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        id=$(_id_of "$line")
        name=$(_name_of "$line")
        printf "  %-30s  %s\n" "$name" "$id" >&2
        docker rm -f "$id"
    done <<< "$matches"
}

cmd_stats() {
    local pattern="${1:-}"
    if [[ -n "$pattern" ]]; then
        local matches
        matches=$(_list_running "$pattern")
        _require_matches "$pattern" "$matches"
        # Pass IDs explicitly to docker stats (bash 3-compatible array build)
        local -a ids=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && ids+=("$(_id_of "$line")")
        done <<< "$matches"
        exec docker stats "${ids[@]}"
    else
        exec docker stats
    fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        ps)                cmd_ps      "$@" ;;
        psa|ps-all)        cmd_psa     "$@" ;;
        logs|log)          cmd_logs    "$@" ;;
        shell|sh|bash)     cmd_shell   "$@" ;;
        exec)              cmd_exec    "$@" ;;
        env)               cmd_env     "$@" ;;
        inspect)           cmd_inspect "$@" ;;
        stop)              cmd_stop    "$@" ;;
        kill)              cmd_kill    "$@" ;;
        rm|remove)         cmd_rm      "$@" ;;
        restart)           cmd_restart "$@" ;;
        stats|stat)        cmd_stats   "$@" ;;
        help|--help|-h)    usage ;;
        *)
            echo -e "${RED}error:${NC} Unknown command: ${BOLD}${command}${NC}" >&2
            echo "" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
