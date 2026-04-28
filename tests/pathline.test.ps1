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
    # Write-Host goes to information stream (6) in PS5+, but also to host
    # Use a workaround: capture via transcript or just test the functions directly
    return $output
}

Write-Host "=== PowerShell tests ==="

# Test the helper functions directly since Write-Host is hard to capture

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

# Restore env
$env:HOME = $null
$env:USERPROFILE = $null

Write-Host ""
Write-Host "Results: $Pass passed, $Fail failed"
if ($Fail -gt 0) { exit 1 }
