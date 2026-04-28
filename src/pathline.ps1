# pathline
#
# Git-aware path display with worktree highlighting. Detects
# .worktrees/<name> segments in paths, verifies each against its
# repo's branch (case-sensitive), and outputs ANSI-colored text.
# Supports arbitrary nesting depth.
#
# Compatible with PowerShell 5.1+ and PowerShell Core 7+.
# Dot-source this file and call Invoke-Pathline to get colored output.

$Script:PathlinePathColor = "cbd4fe"
$Script:PathlineBranchColor = "b4a7d6"

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
    $home = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    if (-not $home) { return $RawPath }
    $normalizedHome = $home.Replace("\", "/")
    if ($RawPath -ne $normalizedHome -and $RawPath.StartsWith("$normalizedHome/")) {
        return "~" + $RawPath.Substring($normalizedHome.Length)
    }
    return $RawPath
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
        [string]$Branch
    )

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

    # Find and verify worktree segments
    $marker = "/.worktrees/"
    $verifiedSegments = @()
    $searchFrom = 0

    while ($true) {
        $markerIdx = $normalized.IndexOf($marker, $searchFrom)
        if ($markerIdx -eq -1) { break }

        $nameStart = $markerIdx + $marker.Length
        if ($nameStart -ge $normalized.Length) { break }

        $afterMarker = $normalized.Substring($nameStart)
        $parts = $afterMarker.Split("/")
        $matched = $false

        $rawOffset = $normalizedRaw.Length - $displayPath.Length

        for ($i = 1; $i -le $parts.Length; $i++) {
            $candidateName = ($parts[0..($i - 1)]) -join "/"
            $candidateRawPath = $normalizedRaw.Substring(0, $nameStart + $rawOffset + $candidateName.Length)

            # Convert back to native separators for filesystem access
            $nativePath = if ($IsWindows -or (-not (Test-Path variable:IsWindows) -and $env:OS -eq "Windows_NT")) {
                $candidateRawPath.Replace("/", "\")
            } else {
                $candidateRawPath
            }

            $gitFile = Join-Path $nativePath ".git"
            if (-not (Test-Path $gitFile)) { continue }

            $wtBranch = Script:Get-GitBranch -Path $nativePath
            if ($wtBranch -ceq $candidateName) {
                $verifiedSegments += @{ nameStart = $nameStart; nameEnd = $nameStart + $candidateName.Length }
                $searchFrom = $nameStart + $candidateName.Length
                $matched = $true
                break
            }

            if ($wtBranch) { break }
        }

        if (-not $matched) {
            $searchFrom = $nameStart
        }
    }

    # Build output
    $pathColor = $Script:PathlinePathColor
    $branchColor = $Script:PathlineBranchColor
    $output = ""

    if ($verifiedSegments.Count -eq 0) {
        $output = Script:ConvertTo-AnsiColor -Text $displayPath -Hex $pathColor
        if ($Branch) {
            $output += " " + (Script:ConvertTo-AnsiColor -Text "($Branch)" -Hex $branchColor)
        }
    } else {
        $pos = 0
        foreach ($seg in $verifiedSegments) {
            if ($pos -lt $seg.nameStart) {
                $output += Script:ConvertTo-AnsiColor -Text $displayPath.Substring($pos, $seg.nameStart - $pos) -Hex $pathColor
            }
            $output += Script:ConvertTo-AnsiColor -Text $displayPath.Substring($seg.nameStart, $seg.nameEnd - $seg.nameStart) -Hex $branchColor
            $pos = $seg.nameEnd
        }
        if ($pos -lt $displayPath.Length) {
            $output += Script:ConvertTo-AnsiColor -Text $displayPath.Substring($pos) -Hex $pathColor
        }

        # Determine if last verified segment is the innermost worktree
        $lastSeg = $verifiedSegments[$verifiedSegments.Count - 1]
        $lastName = $normalized.Substring($lastSeg.nameStart, $lastSeg.nameEnd - $lastSeg.nameStart)
        $innermostIsWorktree = $Branch -and ($lastName -ceq $Branch) -and (
            $normalized.Length -eq $lastSeg.nameEnd -or $normalized[$lastSeg.nameEnd] -eq "/"
        )

        if (-not $innermostIsWorktree -and $Branch) {
            $output += " " + (Script:ConvertTo-AnsiColor -Text "($Branch)" -Hex $branchColor)
        }
    }

    Write-Host "${output}`e[0m"
}

Set-Alias -Name pathline -Value Invoke-Pathline
