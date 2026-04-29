#!/usr/bin/env bash

# Shell tests for pathline.sh, run inside Docker.
# Outputs JSON lines for each test case.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Strip ANSI codes for plain text comparison
strip_ansi() {
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Output a JSON test result
pass() {
    local name="$1"
    echo "{\"name\": \"$name\", \"pass\": true}"
}

fail() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    # Escape backslashes and double quotes for JSON
    expected="${expected//\\/\\\\}"
    expected="${expected//\"/\\\"}"
    actual="${actual//\\/\\\\}"
    actual="${actual//\"/\\\"}"
    echo "{\"name\": \"$name\", \"pass\": false, \"expected\": \"$expected\", \"actual\": \"$actual\"}"
}

assert_contains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$name"
    else
        fail "$name" "contains '$needle'" "$haystack"
    fi
}

assert_not_contains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$name"
    else
        fail "$name" "does not contain '$needle'" "$haystack"
    fi
}

# ---- Setup test repos ----
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create a normal repo
mkdir -p "$TEST_DIR/normalrepo"
git -C "$TEST_DIR/normalrepo" init -q
git -C "$TEST_DIR/normalrepo" commit --allow-empty -m "init" -q

# Create a repo with worktrees
mkdir -p "$TEST_DIR/repo"
git -C "$TEST_DIR/repo" init -q -b main
git -C "$TEST_DIR/repo" commit --allow-empty -m "init" -q
git -C "$TEST_DIR/repo" worktree add "$TEST_DIR/repo/.worktrees/feature/login" -b "feature/login" -q 2>/dev/null

# Arbitrary location worktree
git -C "$TEST_DIR/repo" worktree add "$TEST_DIR/arbitrary-wt" -b "arbitrary-wt" -q 2>/dev/null

# Slashed branch in non-.worktrees/ location
mkdir -p "$TEST_DIR/other/fix"
git -C "$TEST_DIR/repo" worktree add "$TEST_DIR/other/fix/bug" -b "fix/bug" -q 2>/dev/null

# Nested worktree setup: create a sub-repo inside a worktree, then a worktree of that
mkdir -p "$TEST_DIR/repo/.worktrees/feature/login/sub"
git -C "$TEST_DIR/repo/.worktrees/feature/login/sub" init -q -b main
git -C "$TEST_DIR/repo/.worktrees/feature/login/sub" commit --allow-empty -m "init" -q
git -C "$TEST_DIR/repo/.worktrees/feature/login/sub" worktree add \
    "$TEST_DIR/repo/.worktrees/feature/login/sub/.worktrees/fix/inner" -b "fix/inner" -q 2>/dev/null

# Source the script
source "$SCRIPT_DIR/src/pathline.sh"

# ---- Tests ----

# Test: Normal repo
output=$(pathline_render "$TEST_DIR/normalrepo" "main")
plain=$(strip_ansi "$output")
assert_contains "normal repo: shows branch in parens" "$plain" "(main)"
assert_contains "normal repo: shows path" "$plain" "normalrepo"

# Test: No git branch
NOGIT_DIR=$(mktemp -d)
output=$(pathline_render "$NOGIT_DIR" "")
plain=$(strip_ansi "$output")
assert_not_contains "no git: no parens" "$plain" "("
rm -rf "$NOGIT_DIR"

# Test: Worktree in .worktrees/ matching branch
output=$(pathline_render "$TEST_DIR/repo/.worktrees/feature/login" "feature/login")
plain=$(strip_ansi "$output")
assert_contains "worktree match: shows name" "$plain" "feature/login"
assert_not_contains "worktree match: no parens" "$plain" "(feature/login)"

# Test: Worktree branch mismatch
output=$(pathline_render "$TEST_DIR/repo/.worktrees/feature/login" "bugfix/other")
plain=$(strip_ansi "$output")
assert_contains "worktree mismatch: shows branch in parens" "$plain" "(bugfix/other)"

# Test: Subdirectory inside worktree
mkdir -p "$TEST_DIR/repo/.worktrees/feature/login/src"
output=$(pathline_render "$TEST_DIR/repo/.worktrees/feature/login/src" "feature/login")
plain=$(strip_ansi "$output")
assert_contains "worktree subdir: shows /src" "$plain" "/src"
assert_contains "worktree subdir: shows worktree name" "$plain" "feature/login"

# Test: Nested worktrees
output=$(pathline_render "$TEST_DIR/repo/.worktrees/feature/login/sub/.worktrees/fix/inner" "fix/inner")
plain=$(strip_ansi "$output")
assert_contains "nested worktree: shows outer name" "$plain" "feature/login"
assert_contains "nested worktree: shows inner name" "$plain" "fix/inner"
assert_not_contains "nested worktree: no parens for inner" "$plain" "(fix/inner)"

# Test: Custom colors
output=$(pathline_render "$TEST_DIR/normalrepo" "main" "ff5500" "00ff88")
assert_contains "custom colors: path has ff5500 RGB" "$output" "255;85;0"
assert_contains "custom colors: branch has 00ff88 RGB" "$output" "0;255;136"
plain=$(strip_ansi "$output")
assert_contains "custom colors: shows branch" "$plain" "(main)"

# Test: Complex truecolor hex - very dark
output=$(pathline_render "$TEST_DIR/normalrepo" "main" "0a0a0a" "050505")
assert_contains "dark colors: path has 0a0a0a RGB" "$output" "10;10;10"
assert_contains "dark colors: branch has 050505 RGB" "$output" "5;5;5"

# Test: Complex truecolor hex - very light
output=$(pathline_render "$TEST_DIR/normalrepo" "main" "fefefe" "f0f0f0")
assert_contains "light colors: path has fefefe RGB" "$output" "254;254;254"
assert_contains "light colors: branch has f0f0f0 RGB" "$output" "240;240;240"

# Test: Default colors
output=$(pathline_render "$TEST_DIR/normalrepo" "main")
assert_contains "default colors: path has cbd4fe RGB" "$output" "203;212;254"
assert_contains "default colors: branch has b4a7d6 RGB" "$output" "180;167;214"

# Test: Windows-style simulated paths
# Create the git repo first (before changing HOME so git config is found)
WIN_DIR="$TEST_DIR/C:/Users/user/repos"
mkdir -p "$WIN_DIR"
git -C "$WIN_DIR" init -q -b main
git -C "$WIN_DIR" commit --allow-empty -m "init" -q
mkdir -p "$WIN_DIR/.worktrees/feature"
git -C "$WIN_DIR" worktree add "$WIN_DIR/.worktrees/feature/auth" -b "feature/auth" -q 2>/dev/null
# Use a HOME that does not overlap with the simulated Windows path
SAVED_HOME="$HOME"
export HOME="/nonexistent-home"
output=$(pathline_render "$WIN_DIR/.worktrees/feature/auth" "feature/auth")
plain=$(strip_ansi "$output")
assert_contains "windows-sim: shows worktree name" "$plain" "feature/auth"
assert_not_contains "windows-sim: no parens" "$plain" "(feature/auth)"
export HOME="$SAVED_HOME"
