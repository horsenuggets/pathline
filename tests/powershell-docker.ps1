# PowerShell tests for pathline.ps1, run inside Docker.
# Outputs JSON lines for each test case.

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$ScriptRoot/src/pathline.ps1"

function Write-Pass {
    param([string]$Name)
    $escapedName = $Name.Replace("\", "\\").Replace('"', '\"')
    Write-Output "{`"name`": `"$escapedName`", `"pass`": true}"
}

function Write-Fail {
    param([string]$Name, [string]$Expected, [string]$Actual)
    $escapedName = $Name.Replace("\", "\\").Replace('"', '\"')
    $escapedExpected = $Expected.Replace("\", "\\").Replace('"', '\"')
    $escapedActual = $Actual.Replace("\", "\\").Replace('"', '\"')
    Write-Output "{`"name`": `"$escapedName`", `"pass`": false, `"expected`": `"$escapedExpected`", `"actual`": `"$escapedActual`"}"
}

function Assert-Contains {
    param([string]$Name, [string]$Haystack, [string]$Needle)
    if ($Haystack.Contains($Needle)) {
        Write-Pass -Name $Name
    } else {
        Write-Fail -Name $Name -Expected "contains '$Needle'" -Actual $Haystack
    }
}

function Assert-NotContains {
    param([string]$Name, [string]$Haystack, [string]$Needle)
    if (-not $Haystack.Contains($Needle)) {
        Write-Pass -Name $Name
    } else {
        Write-Fail -Name $Name -Expected "does not contain '$Needle'" -Actual $Haystack
    }
}

function Strip-Ansi {
    param([string]$Text)
    return $Text -replace "`e\[[0-9;]*m", ""
}

# Capture Invoke-Pathline output (it uses Write-Host -> information stream)
function Invoke-PathlineCapture {
    param(
        [string]$RawPath,
        [string]$Branch,
        [string]$PathColor,
        [string]$BranchColor
    )
    $params = @{}
    if ($RawPath) { $params["RawPath"] = $RawPath }
    if ($Branch) { $params["Branch"] = $Branch }
    if ($PathColor) { $params["PathColor"] = $PathColor }
    if ($BranchColor) { $params["BranchColor"] = $BranchColor }
    $result = Invoke-Pathline @params 6>&1
    return "$result"
}

# ---- Setup ALL git repos before changing HOME ----
# (git reads ~/.gitconfig so HOME must point to /root during repo creation)
$tempDir = [System.IO.Path]::GetTempPath()
$testDir = Join-Path $tempDir "pathline-test-$(Get-Random)"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

# Normal repo
$normalRepo = Join-Path $testDir "normalrepo"
New-Item -ItemType Directory -Path $normalRepo -Force | Out-Null
git -C $normalRepo init -q 2>$null
git -C $normalRepo commit --allow-empty -m "init" -q 2>$null

# Repo with worktree
$repo = Join-Path $testDir "repo"
New-Item -ItemType Directory -Path $repo -Force | Out-Null
git -C $repo init -q -b main 2>$null
git -C $repo commit --allow-empty -m "init" -q 2>$null
$wtPath = Join-Path $repo ".worktrees/feature/login"
git -C $repo worktree add $wtPath -b "feature/login" -q 2>$null

# Windows-style path simulation repo (must create before HOME changes)
$winDir = Join-Path $testDir "C:/Users/user/repos"
New-Item -ItemType Directory -Path $winDir -Force | Out-Null
git -C $winDir init -q -b main 2>$null
git -C $winDir commit --allow-empty -m "init" -q 2>$null
$winWt = Join-Path $winDir ".worktrees/feature/auth"
git -C $winDir worktree add $winWt -b "feature/auth" -q 2>$null

# NOW set HOME to testDir for tilde substitution tests
$env:HOME = $testDir

# ---- Tests ----

# Test: Get-DisplayPath with home substitution
$result = Script:Get-DisplayPath -RawPath "$testDir/projects/foo"
Assert-Contains -Name "home sub: starts with ~" -Haystack $result -Needle "~"
Assert-Contains -Name "home sub: has path" -Haystack $result -Needle "/projects/foo"
Assert-NotContains -Name "home sub: no full home" -Haystack $result -Needle $testDir

# Test: Display path outside home
$result = Script:Get-DisplayPath -RawPath "/opt/projects/foo"
Assert-Contains -Name "outside home: shows full path" -Haystack $result -Needle "/opt/projects/foo"
Assert-NotContains -Name "outside home: no tilde" -Haystack $result -Needle "~"

# Test: ConvertTo-AnsiColor produces correct RGB
$colored = Script:ConvertTo-AnsiColor -Text "hello" -Hex "cbd4fe"
Assert-Contains -Name "ansi color: has escape" -Haystack $colored -Needle "`e["
Assert-Contains -Name "ansi color: has text" -Haystack $colored -Needle "hello"
Assert-Contains -Name "ansi color: has RGB" -Haystack $colored -Needle "38;2;203;212;254"

# Test: Test-WorktreeRoot rejects .git directories
$dirTest = Join-Path $testDir "wt-dir-test"
New-Item -ItemType Directory -Path $dirTest -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dirTest ".git") -Force | Out-Null
$result = Script:Test-WorktreeRoot -Path $dirTest
if (-not $result) {
    Write-Pass -Name "worktree root: rejects .git directory"
} else {
    Write-Fail -Name "worktree root: rejects .git directory" -Expected "false" -Actual "true"
}
Remove-Item -Recurse -Force $dirTest

# Test: Test-WorktreeRoot accepts .git files
$fileTest = Join-Path $testDir "wt-file-test"
New-Item -ItemType Directory -Path $fileTest -Force | Out-Null
Set-Content -Path (Join-Path $fileTest ".git") -Value "gitdir: /some/path"
$result = Script:Test-WorktreeRoot -Path $fileTest
if ($result) {
    Write-Pass -Name "worktree root: accepts .git file"
} else {
    Write-Fail -Name "worktree root: accepts .git file" -Expected "true" -Actual "false"
}
Remove-Item -Recurse -Force $fileTest

# Test: Normal path shows branch in parens
$output = Invoke-PathlineCapture -RawPath $normalRepo -Branch "main"
$plain = Strip-Ansi "$output"
Assert-Contains -Name "normal path: shows branch in parens" -Haystack $plain -Needle "(main)"

# Test: Worktree where branch matches folder
$output = Invoke-PathlineCapture -RawPath $wtPath -Branch "feature/login"
$plain = Strip-Ansi "$output"
Assert-Contains -Name "worktree match: shows name" -Haystack $plain -Needle "feature/login"
Assert-NotContains -Name "worktree match: no parens" -Haystack $plain -Needle "(feature/login)"

# Test: Worktree branch mismatch shows parens
$output = Invoke-PathlineCapture -RawPath $wtPath -Branch "bugfix/other"
$plain = Strip-Ansi "$output"
Assert-Contains -Name "worktree mismatch: shows branch in parens" -Haystack $plain -Needle "(bugfix/other)"

# Test: Custom truecolor colors
$output = Invoke-PathlineCapture -RawPath $normalRepo -Branch "main" -PathColor "ff5500" -BranchColor "00ff88"
Assert-Contains -Name "custom colors: path has ff5500 RGB" -Haystack $output -Needle "255;85;0"
Assert-Contains -Name "custom colors: branch has 00ff88 RGB" -Haystack $output -Needle "0;255;136"

# Test: Very dark truecolor
$output = Invoke-PathlineCapture -RawPath $normalRepo -Branch "main" -PathColor "0a0a0a" -BranchColor "050505"
Assert-Contains -Name "dark colors: path has 0a0a0a RGB" -Haystack $output -Needle "10;10;10"
Assert-Contains -Name "dark colors: branch has 050505 RGB" -Haystack $output -Needle "5;5;5"

# Test: Very light truecolor
$output = Invoke-PathlineCapture -RawPath $normalRepo -Branch "main" -PathColor "fefefe" -BranchColor "f0f0f0"
Assert-Contains -Name "light colors: path has fefefe RGB" -Haystack $output -Needle "254;254;254"
Assert-Contains -Name "light colors: branch has f0f0f0 RGB" -Haystack $output -Needle "240;240;240"

# Test: Windows-style path simulation
# Set HOME to something that does not overlap with the test path
$savedHome = $env:HOME
$env:HOME = "/nonexistent-home"
$output = Invoke-PathlineCapture -RawPath $winWt -Branch "feature/auth"
$plain = Strip-Ansi "$output"
Assert-Contains -Name "windows-sim: shows worktree name" -Haystack $plain -Needle "feature/auth"
Assert-NotContains -Name "windows-sim: no parens" -Haystack $plain -Needle "(feature/auth)"
$env:HOME = $savedHome

# ---- Cleanup ----
Remove-Item -Recurse -Force $testDir
$env:HOME = $null
