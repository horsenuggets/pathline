# pathline
#
# Git-aware path display with worktree highlighting. Detects worktrees
# by checking for .git FILES (not directories) at path prefixes,
# verifies each against its repo's branch (case-sensitive), and outputs
# ANSI-colored text. Supports arbitrary nesting depth.
#
# Compatible with PowerShell 5.1+ and PowerShell Core 7+.
# Dot-source this file and call Invoke-Pathline to get colored output.

function Script:ConvertTo-AnsiColor {
    param(
        [string]$Text,
        [string]$Hex
    )
    $Hex = $Hex.TrimStart("#")
    $r = [Convert]::ToInt32($Hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(4, 2), 16)
    return "`e[38;2;${r};${g};${b}m${Text}"
}

function Script:Get-GitBranch {
    param([string]$Path)
    try {
        $branch = git -C $Path symbolic-ref --short HEAD 2>$null
        if ($branch) { return $branch.Trim() }
        $branch = git -C $Path rev-parse --short HEAD 2>$null
        if ($branch) { return $branch.Trim() }
    } catch {}
    return $null
}

function Script:Get-DisplayPath {
    param([string]$RawPath)
    $homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    if (-not $homeDir) { return $RawPath }
    $normalizedHome = $homeDir.Replace("\", "/")
    if ($RawPath -ne $normalizedHome -and $RawPath.StartsWith("$normalizedHome/")) {
        return "~" + $RawPath.Substring($normalizedHome.Length)
    }
    return $RawPath
}

function Script:Test-WorktreeRoot {
    param([string]$Path)
    $gitPath = Join-Path $Path ".git"
    if (Test-Path -Path $gitPath -PathType Leaf) {
        return $true
    }
    return $false
}

function Invoke-Pathline {
    <#
    .SYNOPSIS
        Renders a git-aware path with worktree highlighting.
    .PARAMETER RawPath
        Filesystem path to render. Defaults to $PWD.
    .PARAMETER Branch
        Git branch name. Defaults to computed via git.
    #>
    param(
        [Parameter(Position = 0)]
        [string]$RawPath,

        [Parameter(Position = 1)]
        [string]$Branch,

        [Parameter(Position = 2)]
        [string]$PathColor,

        [Parameter(Position = 3)]
        [string]$BranchColor
    )

    if (-not $PathColor) { $PathColor = "cbd4fe" }
    if (-not $BranchColor) { $BranchColor = "b4a7d6" }

    if (-not $RawPath) {
        $RawPath = (Get-Location).Path
    }

    # Normalize separators to forward slashes internally
    $normalizedRaw = $RawPath.Replace("\", "/")
    $displayPath = Script:Get-DisplayPath -RawPath $normalizedRaw
    $normalized = $displayPath.Replace("\", "/")

    if (-not $Branch) {
        $Branch = Script:Get-GitBranch -Path $RawPath
    }

    # Walk path prefixes to find worktree roots
    $segments = $normalized.Split("/")
    $rawOffset = $normalizedRaw.Length - $displayPath.Length
    $verifiedSegments = @()

    for ($i = 1; $i -le $segments.Length; $i++) {
        $prefix = ($segments[0..($i - 1)]) -join "/"
        $rawPrefix = $normalizedRaw.Substring(0, $prefix.Length + $rawOffset)

        # Convert to native path for filesystem check
        $nativePath = if ($IsWindows -or (-not (Test-Path variable:IsWindows) -and $env:OS -eq "Windows_NT")) {
            $rawPrefix.Replace("/", "\")
        } else {
            $rawPrefix
        }

        if (-not $nativePath -or -not (Script:Test-WorktreeRoot -Path $nativePath)) { continue }

        $wtBranch = Script:Get-GitBranch -Path $nativePath
        if (-not $wtBranch) { continue }

        # Check if trailing segments match the branch
        $branchParts = $wtBranch.Split("/")
        $branchPartCount = $branchParts.Length

        if ($branchPartCount -gt $i) { continue }

        $trailingSegments = $segments[($i - $branchPartCount)..($i - 1)]
        $trailing = $trailingSegments -join "/"

        if ($trailing -ceq $wtBranch) {
            # Calculate character positions
            if ($i - $branchPartCount -gt 0) {
                $beforeTrailing = ($segments[0..($i - $branchPartCount - 1)]) -join "/"
                $nameStart = $beforeTrailing.Length + 1
            } else {
                $nameStart = 0
            }
            $nameEnd = $nameStart + $trailing.Length
            $verifiedSegments += @{ nameStart = $nameStart; nameEnd = $nameEnd }
        }
    }

    # Build output
    $output = ""

    if ($verifiedSegments.Count -eq 0) {
        $output = Script:ConvertTo-AnsiColor -Text $displayPath -Hex $PathColor
        if ($Branch) {
            $output += " " + (Script:ConvertTo-AnsiColor -Text "($Branch)" -Hex $BranchColor)
        }
    } else {
        $pos = 0
        foreach ($seg in $verifiedSegments) {
            if ($pos -lt $seg.nameStart) {
                $output += Script:ConvertTo-AnsiColor -Text $displayPath.Substring($pos, $seg.nameStart - $pos) -Hex $PathColor
            }
            $output += Script:ConvertTo-AnsiColor -Text $displayPath.Substring($seg.nameStart, $seg.nameEnd - $seg.nameStart) -Hex $BranchColor
            $pos = $seg.nameEnd
        }
        if ($pos -lt $displayPath.Length) {
            $output += Script:ConvertTo-AnsiColor -Text $displayPath.Substring($pos) -Hex $PathColor
        }

        # Determine if last verified segment is the innermost worktree
        $lastSeg = $verifiedSegments[$verifiedSegments.Count - 1]
        $lastName = $normalized.Substring($lastSeg.nameStart, $lastSeg.nameEnd - $lastSeg.nameStart)
        $innermostIsWorktree = $Branch -and ($lastName -ceq $Branch) -and (
            $normalized.Length -eq $lastSeg.nameEnd -or $normalized[$lastSeg.nameEnd] -eq "/"
        )

        if (-not $innermostIsWorktree -and $Branch) {
            $output += " " + (Script:ConvertTo-AnsiColor -Text "($Branch)" -Hex $BranchColor)
        }
    }

    Write-Host "${output}`e[0m"
}

Set-Alias -Name pathline -Value Invoke-Pathline
