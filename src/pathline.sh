#!/usr/bin/env bash

# pathline
#
# Git-aware path display with worktree highlighting. Detects
# .worktrees/<name> segments in paths, verifies each against its
# repo's branch (case-sensitive), and outputs ANSI-colored text.
# Supports arbitrary nesting depth.
#
# Compatible with bash and zsh. Source this file and call
# pathline_render to get colored path output.

# Colors (hex values for truecolor terminals)
PATHLINE_PATH_COLOR="${PATHLINE_PATH_COLOR:-cbd4fe}"
PATHLINE_BRANCH_COLOR="${PATHLINE_BRANCH_COLOR:-b4a7d6}"

pathline_color() {
    local text="$1"
    local hex="${2#"#"}"
    local r=$(printf "%d" "0x${hex:0:2}")
    local g=$(printf "%d" "0x${hex:2:2}")
    local b=$(printf "%d" "0x${hex:4:2}")
    echo -n "\033[38;2;${r};${g};${b}m${text}"
}

pathline_get_branch() {
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
    fi
}

pathline_get_path() {
    local working_dir="$PWD"
    local home_dir="$HOME"
    if [[ "$working_dir" == "$home_dir"* ]]; then
        echo "~${working_dir#"$home_dir"}"
    else
        echo "$working_dir"
    fi
}

# Split a string by "/" into an array. Works in both bash and zsh.
_pathline_split() {
    local str="$1"
    local IFS="/"
    if [[ -n "$ZSH_VERSION" ]]; then
        _pathline_parts=("${(@s:/:)str}")
    else
        read -ra _pathline_parts <<< "$str"
    fi
}

# Main render function. Outputs the path with ANSI color codes,
# highlighting verified worktree names and appending the git branch
# when appropriate.
pathline_render() {
    local custom_path
    custom_path=$(pathline_get_path)
    local git_branch
    git_branch=$(pathline_get_branch)
    local marker="/.worktrees/"
    local remaining="$custom_path"
    local built=""
    local raw_built=""
    local any_match=false
    local last_match_is_innermost=false

    while [[ "$remaining" == *"$marker"* ]]; do
        local before="${remaining%%"$marker"*}"
        local after="${remaining#*"$marker"}"

        if [[ -z "$after" ]]; then
            built+="$(pathline_color "${before}${marker}" "$PATHLINE_PATH_COLOR")"
            raw_built+="${before}${marker}"
            remaining=""
            break
        fi

        # Try progressively longer segments to find the worktree root.
        # Branch names can contain slashes (e.g. feature/auth).
        local matched=false
        _pathline_split "$after"
        local candidate=""

        for part in "${_pathline_parts[@]}"; do
            if [[ -z "$candidate" ]]; then
                candidate="$part"
            else
                candidate="${candidate}/${part}"
            fi

            # Use raw_built (no ANSI codes) for filesystem path
            local raw_candidate="${raw_built}${before}${marker}${candidate}"
            raw_candidate="${raw_candidate/#\~/$HOME}"

            # Only check git branch if this is actually a worktree root
            [[ -e "$raw_candidate/.git" ]] || continue
            local wt_branch
            wt_branch=$(cd "$raw_candidate" 2>/dev/null && git symbolic-ref --short HEAD 2>/dev/null)

            if [[ -n "$wt_branch" ]] && [[ "$wt_branch" == "$candidate" ]]; then
                built+="$(pathline_color "${before}${marker}" "$PATHLINE_PATH_COLOR")"
                built+="$(pathline_color "$candidate" "$PATHLINE_BRANCH_COLOR")"
                raw_built+="${before}${marker}${candidate}"
                remaining="${after#"$candidate"}"
                any_match=true

                if [[ "$wt_branch" == "$git_branch" ]]; then
                    if [[ -z "$remaining" ]] || [[ "$remaining" == /* ]]; then
                        last_match_is_innermost=true
                    fi
                else
                    last_match_is_innermost=false
                fi
                matched=true
                break
            fi

            if [[ -n "$wt_branch" ]]; then break; fi
        done

        if [[ "$matched" == false ]]; then
            built+="$(pathline_color "${before}${marker}" "$PATHLINE_PATH_COLOR")"
            raw_built+="${before}${marker}"
            remaining="$after"
        fi
    done

    if [[ -n "$remaining" ]]; then
        built+="$(pathline_color "$remaining" "$PATHLINE_PATH_COLOR")"
    fi

    local output=""
    if [[ "$any_match" == true ]]; then
        output="$built"
        if [[ "$last_match_is_innermost" == false ]] && [[ -n "$git_branch" ]]; then
            output+=" $(pathline_color "($git_branch)" "$PATHLINE_BRANCH_COLOR")"
        fi
    else
        output="$(pathline_color "$custom_path" "$PATHLINE_PATH_COLOR")"
        if [[ -n "$git_branch" ]]; then
            output+=" $(pathline_color "($git_branch)" "$PATHLINE_BRANCH_COLOR")"
        fi
    fi

    echo -e "${output}\033[0m"
}
