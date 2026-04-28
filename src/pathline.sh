#!/usr/bin/env bash

# pathline
#
# Git-aware path display with worktree highlighting. Detects worktrees
# by checking for .git FILES (not directories) at path prefixes,
# verifies each against its repo's branch (case-sensitive), and outputs
# ANSI-colored text. Supports arbitrary nesting depth.
#
# Compatible with bash and zsh. Source this file and call
# pathline_render to get colored path output.

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

# Check if a path is a worktree root (.git is a file, not a directory)
_pathline_is_worktree() {
    local path="$1"
    [[ -f "$path/.git" ]]
}

# Main render function. Outputs the path with ANSI color codes,
# highlighting verified worktree names and appending the git branch
# when appropriate.
#
# Usage: pathline_render [raw_path] [branch] [path_color] [branch_color]
#   raw_path     - Filesystem path (default: $PWD)
#   branch       - Git branch name (default: computed via git)
#   path_color   - Hex color for path segments (default: cbd4fe)
#   branch_color - Hex color for branch segments (default: b4a7d6)
pathline_render() {
    local raw_path="${1:-$PWD}"
    local path_color="${3:-cbd4fe}"
    local branch_color="${4:-b4a7d6}"
    local custom_path
    if [[ -n "${1:-}" ]]; then
        local home_dir="$HOME"
        if [[ "$raw_path" == "$home_dir"* ]]; then
            custom_path="~${raw_path#"$home_dir"}"
        else
            custom_path="$raw_path"
        fi
    else
        custom_path=$(pathline_get_path)
    fi
    # Normalize backslashes to forward slashes for matching
    custom_path="${custom_path//\\//}"
    raw_path="${raw_path//\\//}"
    local git_branch="${2:-$(cd "$raw_path" 2>/dev/null && pathline_get_branch)}"

    # Split display path into segments
    local IFS="/"
    local -a path_segments
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        path_segments=("${(@s:/:)custom_path}")
    else
        read -ra path_segments <<< "$custom_path"
    fi
    unset IFS

    local raw_offset=$(( ${#raw_path} - ${#custom_path} ))

    # Walk prefixes to find worktree roots
    local -a highlight_starts=()
    local -a highlight_ends=()
    local prefix=""

    for (( i=0; i<${#path_segments[@]}; i++ )); do
        if [[ $i -eq 0 ]]; then
            prefix="${path_segments[0]}"
        else
            prefix="${prefix}/${path_segments[$i]}"
        fi

        # Compute the raw path for this prefix
        local raw_prefix="${raw_path:0:$(( ${#prefix} + raw_offset ))}"
        # Expand ~ for filesystem checks
        local check_path="${raw_prefix/#\~/$HOME}"

        if ! _pathline_is_worktree "$check_path"; then
            continue
        fi

        # Get branch for this worktree
        local wt_branch
        wt_branch=$(cd "$check_path" 2>/dev/null && git symbolic-ref --short HEAD 2>/dev/null)
        [[ -z "$wt_branch" ]] && continue

        # Check if trailing segments match the branch
        local branch_slash_count
        branch_slash_count=$(echo "$wt_branch" | tr -cd '/' | wc -c)
        branch_slash_count=$(( branch_slash_count + 1 ))  # number of parts

        if (( branch_slash_count > i + 1 )); then
            continue
        fi

        # Build trailing from segments
        local trailing_start=$(( i + 1 - branch_slash_count ))
        local trailing=""
        for (( j=trailing_start; j<=i; j++ )); do
            if [[ -z "$trailing" ]]; then
                trailing="${path_segments[$j]}"
            else
                trailing="${trailing}/${path_segments[$j]}"
            fi
        done

        if [[ "$trailing" == "$wt_branch" ]]; then
            # Calculate character positions using prefix length
            # prefix ends at the worktree root, trailing is the branch name at the end
            local name_start=$(( ${#prefix} - ${#trailing} ))
            local name_end=${#prefix}
            highlight_starts+=("$name_start")
            highlight_ends+=("$name_end")
        fi
    done

    local output=""

    if [[ ${#highlight_starts[@]} -eq 0 ]]; then
        output="$(pathline_color "$custom_path" "$path_color")"
        if [[ -n "$git_branch" ]]; then
            output+=" $(pathline_color "($git_branch)" "$branch_color")"
        fi
    else
        local pos=0
        for (( k=0; k<${#highlight_starts[@]}; k++ )); do
            local hs="${highlight_starts[$k]}"
            local he="${highlight_ends[$k]}"
            if (( pos < hs )); then
                output+="$(pathline_color "${custom_path:$pos:$((hs - pos))}" "$path_color")"
            fi
            output+="$(pathline_color "${custom_path:$hs:$((he - hs))}" "$branch_color")"
            pos=$he
        done
        if (( pos < ${#custom_path} )); then
            output+="$(pathline_color "${custom_path:$pos}" "$path_color")"
        fi

        # Check if last highlight is the innermost worktree
        local last_hs="${highlight_starts[${#highlight_starts[@]}-1]}"
        local last_he="${highlight_ends[${#highlight_ends[@]}-1]}"
        local last_name="${custom_path:$last_hs:$((last_he - last_hs))}"
        local last_match_is_innermost=false

        if [[ -n "$git_branch" ]] && [[ "$last_name" == "$git_branch" ]]; then
            if [[ ${#custom_path} -eq $last_he ]] || [[ "${custom_path:$last_he:1}" == "/" ]]; then
                last_match_is_innermost=true
            fi
        fi

        if [[ "$last_match_is_innermost" == false ]] && [[ -n "$git_branch" ]]; then
            output+=" $(pathline_color "($git_branch)" "$branch_color")"
        fi
    fi

    echo -e "${output}\033[0m"
}
