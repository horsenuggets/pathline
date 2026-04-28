# pathline PowerShell tests
# Simple assertion-based tests for Invoke-Pathline

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$ScriptRoot/src/pathline.ps1"

$Pass = 0
$Fail = 0

function Assert-Contains {
    param([string]$Label, [string]$Haystack, [string]$Needle)
    if ($Haystack.Contains($Needle)) {
        $script:Pass++
        Write-Host "  PASS: $Label"
    } else {
        $script:Fail++
        Write-Host "  FAIL: $Label"
        Write-Host "    expected to contain: $Needle"
        Write-Host "    got: $Haystack"
    }
}

function Assert-NotContains {
    param([string]$Label, [string]$Haystack, [string]$Needle)
    if (-not $Haystack.Contains($Needle)) {
        $script:Pass++
        Write-Host "  PASS: $Label"
    } else {
        $script:Fail++
        Write-Host "  FAIL: $Label"
        Write-Host "    expected NOT to contain: $Needle"
        Write-Host "    got: $Haystack"
    }
}

function Strip-Ansi {
    param([string]$Text)
    return $Text -replace "`e\[[0-9;]*m", ""
}

# Capture Write-Host output by redirecting information stream
function Invoke-PathlineCapture {
    param([string]$RawPath, [string]$Branch)
    $output = if ($Branch) {
        (Invoke-Pathline -RawPath $RawPath -Branch $Branch) 6>&1
    } else {
        (Invoke-Pathline -RawPath $RawPath) 6>&1
    }
    return $output
}

Write-Host "=== PowerShell tests ==="

# Test 1: Get-DisplayPath with home substitution
Write-Host "Test 1: Display path with home substitution"
$env:HOME = "/home/user"
$result = Script:Get-DisplayPath -RawPath "/home/user/projects/foo"
Assert-Contains "starts with ~" $result "~"
Assert-Contains "has path" $result "/projects/foo"
Assert-NotContains "no full home" $result "/home/user/projects"

# Test 2: Display path outside home
Write-Host "Test 2: Display path outside home"
$result = Script:Get-DisplayPath -RawPath "/opt/projects/foo"
Assert-Contains "shows full path" $result "/opt/projects/foo"
Assert-NotContains "no tilde" $result "~"

# Test 3: Windows-style path normalization in display
Write-Host "Test 3: Windows path normalization"
$env:USERPROFILE = "C:/Users/dev"
$env:HOME = ""
$result = Script:Get-DisplayPath -RawPath "C:/Users/dev/repo"
Assert-Contains "substitutes home" $result "~"
Assert-Contains "has repo" $result "/repo"

# Test 4: ConvertTo-AnsiColor produces escape sequences
Write-Host "Test 4: ANSI color output"
$colored = Script:ConvertTo-AnsiColor -Text "hello" -Hex "cbd4fe"
Assert-Contains "has escape sequence" $colored "`e["
Assert-Contains "has text" $colored "hello"
Assert-Contains "has RGB values" $colored "38;2;203;212;254"

# Test 5: Test-WorktreeRoot returns false for directories
Write-Host "Test 5: Test-WorktreeRoot rejects directories"
$tempDir = [System.IO.Path]::GetTempPath()
$testDir = Join-Path $tempDir "pathline-test-$(Get-Random)"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $testDir ".git") -Force | Out-Null
$result = Script:Test-WorktreeRoot -Path $testDir
if (-not $result) {
    $script:Pass++
    Write-Host "  PASS: .git directory is not a worktree"
} else {
    $script:Fail++
    Write-Host "  FAIL: .git directory should not be a worktree"
}
Remove-Item -Recurse -Force $testDir

# Test 6: Test-WorktreeRoot returns true for files
Write-Host "Test 6: Test-WorktreeRoot accepts files"
$testDir2 = Join-Path $tempDir "pathline-test-$(Get-Random)"
New-Item -ItemType Directory -Path $testDir2 -Force | Out-Null
Set-Content -Path (Join-Path $testDir2 ".git") -Value "gitdir: /some/path"
$result = Script:Test-WorktreeRoot -Path $testDir2
if ($result) {
    $script:Pass++
    Write-Host "  PASS: .git file is a worktree"
} else {
    $script:Fail++
    Write-Host "  FAIL: .git file should be a worktree"
}
Remove-Item -Recurse -Force $testDir2

# Test 7: Normal path (no worktree) shows branch in parens
Write-Host "Test 7: Normal path shows branch in parens"
$tempRepo = Join-Path $tempDir "pathline-test-repo-$(Get-Random)"
New-Item -ItemType Directory -Path $tempRepo -Force | Out-Null
git -C $tempRepo init -q -b main 2>$null
git -C $tempRepo commit --allow-empty -m "init" -q 2>$null
$env:HOME = $tempDir
$output = & { Invoke-Pathline -RawPath $tempRepo -Branch "main" } 6>&1
$plain = Strip-Ansi "$output"
Assert-Contains "shows branch in parens" "$plain" "(main)"
Remove-Item -Recurse -Force $tempRepo

# Test 8: Worktree where branch matches folder highlights the name
Write-Host "Test 8: Worktree branch matches folder"
$tempRepo2 = Join-Path $tempDir "pathline-test-wt-$(Get-Random)"
New-Item -ItemType Directory -Path $tempRepo2 -Force | Out-Null
git -C $tempRepo2 init -q -b main 2>$null
git -C $tempRepo2 commit --allow-empty -m "init" -q 2>$null
$wtPath = Join-Path $tempRepo2 ".worktrees/feature/login"
git -C $tempRepo2 worktree add $wtPath -b "feature/login" -q 2>$null
$env:HOME = $tempDir
$output = & { Invoke-Pathline -RawPath $wtPath -Branch "feature/login" } 6>&1
$plain = Strip-Ansi "$output"
Assert-Contains "shows worktree name" "$plain" "feature/login"
Assert-NotContains "no parens when branch matches" "$plain" "(feature/login)"
Remove-Item -Recurse -Force $tempRepo2

# Test 9: Worktree where branch doesn't match shows parens
Write-Host "Test 9: Worktree branch mismatch shows parens"
$tempRepo3 = Join-Path $tempDir "pathline-test-mismatch-$(Get-Random)"
New-Item -ItemType Directory -Path $tempRepo3 -Force | Out-Null
git -C $tempRepo3 init -q -b main 2>$null
git -C $tempRepo3 commit --allow-empty -m "init" -q 2>$null
$wtPath3 = Join-Path $tempRepo3 ".worktrees/feature/login"
git -C $tempRepo3 worktree add $wtPath3 -b "feature/login" -q 2>$null
$env:HOME = $tempDir
$output = & { Invoke-Pathline -RawPath $wtPath3 -Branch "bugfix/other" } 6>&1
$plain = Strip-Ansi "$output"
Assert-Contains "shows different branch in parens" "$plain" "(bugfix/other)"
Remove-Item -Recurse -Force $tempRepo3

# Test 10: Color output contains ANSI codes
Write-Host "Test 10: Color output contains ANSI codes"
$env:HOME = "/home/user"
$colored = Script:ConvertTo-AnsiColor -Text "test" -Hex "b4a7d6"
Assert-Contains "has ANSI escape" $colored "`e[38;2;"
Assert-Contains "has RGB for branch color" $colored "180;167;214"

# Test 11: Color parameters are overridable
Write-Host "Test 11: Color parameters are overridable"
$customColor = Script:ConvertTo-AnsiColor -Text "custom" -Hex "ff0000"
Assert-Contains "custom color has red RGB" $customColor "255;0;0"

# Restore env
$env:HOME = $null
$env:USERPROFILE = $null

Write-Host ""
Write-Host "Results: $Pass passed, $Fail failed"
if ($Fail -gt 0) { exit 1 }
