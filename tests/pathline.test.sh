#!/usr/bin/env bash

# Simple test harness for pathline.sh
# Sources the script and tests output with mocked git commands.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label"
        echo "    expected to contain: $needle"
        echo "    got: $haystack"
    fi
}

assert_not_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label"
        echo "    expected NOT to contain: $needle"
        echo "    got: $haystack"
    fi
}

# Strip ANSI codes for easier assertion
strip_ansi() {
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# ---- Setup test repos ----
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create a normal repo
mkdir -p "$TEST_DIR/normalrepo"
git -C "$TEST_DIR/normalrepo" init -q
git -C "$TEST_DIR/normalrepo" commit --allow-empty -m "init" -q

# Create a worktree structure with a real git worktree
mkdir -p "$TEST_DIR/repo"
git -C "$TEST_DIR/repo" init -q -b main
git -C "$TEST_DIR/repo" commit --allow-empty -m "init" -q
git -C "$TEST_DIR/repo" worktree add "$TEST_DIR/repo/.worktrees/feature/login" -b "feature/login" -q 2>/dev/null

# Source the script
source "$SCRIPT_DIR/src/pathline.sh"

echo "=== Shell tests ==="

# Test 1: Normal repo with explicit path and branch
echo "Test 1: Normal repo path with branch"
output=$(pathline_render "$TEST_DIR/normalrepo" "main")
plain=$(strip_ansi "$output")
assert_contains "shows branch in parens" "$plain" "(main)"
assert_contains "shows path" "$plain" "normalrepo"

# Test 2: No branch provided, no git
echo "Test 2: Path with no git repo"
NOGIT_DIR=$(mktemp -d)
output=$(pathline_render "$NOGIT_DIR" "")
plain=$(strip_ansi "$output")
assert_not_contains "no parens without branch" "$plain" "("
rm -rf "$NOGIT_DIR"

# Test 3: Worktree path where branch matches folder
echo "Test 3: Worktree matching branch"
output=$(pathline_render "$TEST_DIR/repo/.worktrees/feature/login" "feature/login")
plain=$(strip_ansi "$output")
assert_contains "shows worktree name" "$plain" "feature/login"
assert_not_contains "no parens when worktree matches" "$plain" "(feature/login)"

# Test 4: Default path (uses $PWD)
echo "Test 4: Default path uses PWD"
pushd "$TEST_DIR/normalrepo" > /dev/null
output=$(pathline_render)
plain=$(strip_ansi "$output")
assert_contains "shows normalrepo in output" "$plain" "normalrepo"
popd > /dev/null

# Test 5: Backslash path normalization
echo "Test 5: Backslash normalization"
# Create a path string with backslashes (simulating Git Bash on Windows)
output=$(pathline_render "$TEST_DIR/repo/.worktrees/feature/login" "feature/login")
plain=$(strip_ansi "$output")
assert_contains "handles forward slashes" "$plain" "feature/login"

# Test 6: Subdirectory inside worktree
echo "Test 6: Subdirectory inside worktree"
mkdir -p "$TEST_DIR/repo/.worktrees/feature/login/src"
output=$(pathline_render "$TEST_DIR/repo/.worktrees/feature/login/src" "feature/login")
plain=$(strip_ansi "$output")
assert_contains "shows subdir" "$plain" "/src"
assert_contains "shows worktree name" "$plain" "feature/login"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
