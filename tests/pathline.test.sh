#!/usr/bin/env bash

# Simple test harness for pathline.sh
# Sources the script and tests output with real git worktrees.

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

# Create a worktree in .worktrees/ (traditional location)
mkdir -p "$TEST_DIR/repo"
git -C "$TEST_DIR/repo" init -q -b main
git -C "$TEST_DIR/repo" commit --allow-empty -m "init" -q
git -C "$TEST_DIR/repo" worktree add "$TEST_DIR/repo/.worktrees/feature/login" -b "feature/login" -q 2>/dev/null

# Create a worktree in an arbitrary location (NOT .worktrees/)
git -C "$TEST_DIR/repo" worktree add "$TEST_DIR/arbitrary-wt" -b "arbitrary-wt" -q 2>/dev/null

# Create a worktree with slashed branch in a non-.worktrees/ location
mkdir -p "$TEST_DIR/other/fix"
git -C "$TEST_DIR/repo" worktree add "$TEST_DIR/other/fix/bug" -b "fix/bug" -q 2>/dev/null

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

# Test 3: Worktree in .worktrees/ where branch matches folder
echo "Test 3: Worktree in .worktrees/ matching branch"
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

# Test 7: Worktree NOT in .worktrees/ folder (arbitrary location)
echo "Test 7: Worktree in arbitrary location"
output=$(pathline_render "$TEST_DIR/arbitrary-wt" "arbitrary-wt")
plain=$(strip_ansi "$output")
assert_contains "shows worktree name" "$plain" "arbitrary-wt"
assert_not_contains "no parens when worktree matches" "$plain" "(arbitrary-wt)"

# Test 8: Worktree with slashed branch in non-.worktrees/ location
echo "Test 8: Slashed branch in arbitrary location"
output=$(pathline_render "$TEST_DIR/other/fix/bug" "fix/bug")
plain=$(strip_ansi "$output")
assert_contains "shows branch segments" "$plain" "fix/bug"
assert_not_contains "no parens when worktree matches" "$plain" "(fix/bug)"

# Test 9: Custom color args
echo "Test 9: Custom color args"
output=$(pathline_render "$TEST_DIR/normalrepo" "main" "ff0000" "00ff00")
assert_contains "output contains ANSI escape" "$output" "[38;2;"
plain=$(strip_ansi "$output")
assert_contains "shows branch in parens" "$plain" "(main)"

# Test 10: Default colors without explicit args
echo "Test 10: Default colors without explicit args"
output=$(pathline_render "$TEST_DIR/normalrepo" "main")
assert_contains "default path color has cbd4fe RGB" "$output" "203;212;254"
assert_contains "default branch color has b4a7d6 RGB" "$output" "180;167;214"

# Test 11: Regular clone (.git is directory) should NOT highlight
echo "Test 11: Regular clone not highlighted"
output=$(pathline_render "$TEST_DIR/repo" "main")
plain=$(strip_ansi "$output")
assert_contains "shows branch in parens for regular clone" "$plain" "(main)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
