#!/usr/bin/env bash

# pathline
#
# Renders every example from the README against real temporary repositories so the
# colors can be checked at a glance. Run it with `npm run preview` or
# `bash scripts/preview.sh`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
source "$SCRIPT_DIR/src/pathline.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Fixture commits must work without a configured Git identity, and without touching the
# user's global configuration.
export GIT_AUTHOR_NAME="pathline preview"
export GIT_AUTHOR_EMAIL="pathline-preview@example.com"
export GIT_COMMITTER_NAME="pathline preview"
export GIT_COMMITTER_EMAIL="pathline-preview@example.com"

# Preview with the classic ANSI blue and yellow that terminal prompts typically use,
# rather than the truecolor defaults.
PREVIEW_PATH_COLOR='\033[0;34m'
PREVIEW_BRANCH_COLOR='\033[0;33m'
PREVIEW_MISSING_COLOR='\033[0;90m'

# Print a labeled example.
show() {
    local label="$1"
    local path="$2"
    local branch="${3:-}"
    printf '\n%s\n' "$label"
    pathline_render "$path" "$branch" "$PREVIEW_PATH_COLOR" "$PREVIEW_BRANCH_COLOR" "$PREVIEW_MISSING_COLOR"
    echo
}

# ---- Build the fixtures ----

# Regular repository with a main branch
PROJECT="$TEST_DIR/git/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q -b main
git -C "$PROJECT" commit -q --allow-empty -m "init"

# Worktree whose folder name matches its branch
WORKTREE="$PROJECT/.wt/feature/auth"
git -C "$PROJECT" worktree add -q "$WORKTREE" -b "feature/auth" 2>/dev/null
mkdir -p "$WORKTREE/src/components"

# Worktree nested inside a sub-repository within the outer worktree
NESTED_REPO="$WORKTREE/sub"
mkdir -p "$NESTED_REPO"
git -C "$NESTED_REPO" init -q -b main
git -C "$NESTED_REPO" commit -q --allow-empty -m "init"
NESTED_WORKTREE="$NESTED_REPO/.wt/bugfix/inner"
git -C "$NESTED_REPO" worktree add -q "$NESTED_WORKTREE" -b "bugfix/inner" 2>/dev/null

# Worktree whose folder name does not match its branch
MISMATCHED_WORKTREE="$PROJECT/.wt/old-name"
git -C "$PROJECT" worktree add -q "$MISMATCHED_WORKTREE" -b "bugfix/renamed" 2>/dev/null

# Subdirectory of the worktree that is deleted, to show all three colors at once
GONE_SUBDIR="$WORKTREE/src/gone"
mkdir -p "$GONE_SUBDIR"
rmdir "$GONE_SUBDIR"

# Windows-style path, simulated with folders that include a drive letter
WINDOWS_REPO="$TEST_DIR/C:/Users/user/repos"
mkdir -p "$WINDOWS_REPO"
git -C "$WINDOWS_REPO" init -q -b main
git -C "$WINDOWS_REPO" commit -q --allow-empty -m "init"
git -C "$WINDOWS_REPO" worktree add -q "$WINDOWS_REPO/.wt/feature/auth" -b "feature/auth" 2>/dev/null

# Directory that is deleted while it pretends to be the current working directory
DELETED="$TEST_DIR/path/to/nested/folder"
mkdir -p "$DELETED"
rmdir "$DELETED" "$TEST_DIR/path/to/nested"

# Show every path relative to the temporary directory, the way the README does.
export HOME="$TEST_DIR"

# ---- Examples ----

echo "pathline preview"

show "Regular repository (branch in parentheses)" "$PROJECT" "main"

show "Worktree root (branch matches folder name)" "$WORKTREE" "feature/auth"

show "Worktree with a subdirectory" "$WORKTREE/src/components" "feature/auth"

show "Nested worktrees (all matching names highlighted)" "$NESTED_WORKTREE" "bugfix/inner"

show "Worktree where the folder name does not match the branch" "$MISMATCHED_WORKTREE"

show "Worktree with a deleted subdirectory (all three colors)" "$GONE_SUBDIR"

show "Home directory without a git repo" "$TEST_DIR" ""

# Render from inside the temporary directory so the simulated path stays drive-relative.
(
    cd "$TEST_DIR"
    show "Windows-style path in a worktree (simulated with a drive folder)" \
        "C:/Users/user/repos/.wt/feature/auth" "feature/auth"
)

show "Deleted directory (missing part in gray)" "$DELETED"
