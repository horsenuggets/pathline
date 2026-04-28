/*

pathline

Git-aware path display with worktree highlighting. Detects
.worktrees/<name> segments in paths, verifies each against its
repo's branch (case-sensitive), and returns colored segments for
terminal rendering. Supports arbitrary nesting depth.

*/

import { execSync } from "node:child_process"
import { existsSync } from "node:fs"

export interface PathSegment {
    text: string
    color: "path" | "branch"
}

/**
 * Get the git branch for a directory, or undefined if not in a git repo.
 */
function getGitBranch(cwd: string): string | undefined {
    try {
        return (
            execSync("git symbolic-ref --short HEAD", {
                cwd,
                stdio: ["pipe", "pipe", "pipe"],
                timeout: 2000,
            })
                .toString()
                .trim() || undefined
        )
    } catch {
        try {
            return (
                execSync("git rev-parse --short HEAD", {
                    cwd,
                    stdio: ["pipe", "pipe", "pipe"],
                    timeout: 2000,
                })
                    .toString()
                    .trim() || undefined
            )
        } catch {
            return undefined
        }
    }
}

/**
 * Replace the home directory prefix with ~ for display.
 */
function toDisplayPath(rawPath: string): string {
    const isWindows = process.platform === "win32"
    const home = process.env.HOME || process.env.USERPROFILE || ""
    if (!isWindows && home && rawPath !== home && rawPath.startsWith(home + "/")) {
        return "~" + rawPath.slice(home.length)
    }
    return rawPath
}

/**
 * Find and verify all .worktrees/<name> segments in the path. For each
 * /.worktrees/ marker, probes git to find the worktree root and verifies
 * the folder name matches the branch (case-sensitive). Supports arbitrary
 * nesting depth (worktrees inside submodules inside worktrees, etc.).
 */
function findVerifiedWorktrees(
    displayPath: string,
    rawPath: string,
): Array<{ nameStart: number; nameEnd: number }> {
    const normalized = displayPath.replace(/\\/g, "/")
    const marker = "/.worktrees/"
    const rawOffset = rawPath.length - displayPath.length
    const results: Array<{ nameStart: number; nameEnd: number }> = []

    let searchFrom = 0
    while (true) {
        const markerIdx = normalized.indexOf(marker, searchFrom)
        if (markerIdx === -1) break

        const nameStart = markerIdx + marker.length
        if (nameStart >= normalized.length) break

        const afterMarker = normalized.slice(nameStart)
        const parts = afterMarker.split("/")
        let matched = false

        for (let i = 1; i <= parts.length; i++) {
            const candidateName = parts.slice(0, i).join("/")
            const candidateRawPath = rawPath.slice(0, nameStart + rawOffset + candidateName.length)

            if (!existsSync(candidateRawPath + "/.git")) continue
            const branch = getGitBranch(candidateRawPath)

            if (branch === candidateName) {
                results.push({ nameStart, nameEnd: nameStart + candidateName.length })
                searchFrom = nameStart + candidateName.length
                matched = true
                break
            }

            if (branch) break
        }

        if (!matched) {
            searchFrom = nameStart
        }
    }

    return results
}

/**
 * Build a pathline from a raw filesystem path. Returns an array of colored
 * segments representing a git-aware path display with worktree highlighting.
 *
 * The home directory prefix is automatically replaced with ~ for display.
 * If branch is not provided, it is computed via git.
 *
 * @param rawPath - The actual filesystem path
 * @param branch - The innermost git branch (computed if omitted)
 */
export function buildPathline(rawPath: string, branch?: string): PathSegment[] {
    const displayPath = toDisplayPath(rawPath)
    const normalized = displayPath.replace(/\\/g, "/")
    const resolvedBranch = branch ?? getGitBranch(rawPath)
    const verifiedSegments = findVerifiedWorktrees(displayPath, rawPath)

    if (verifiedSegments.length === 0) {
        const segments: PathSegment[] = [{ text: displayPath, color: "path" }]
        if (resolvedBranch) {
            segments.push({ text: ` (${resolvedBranch})`, color: "branch" })
        }
        return segments
    }

    const segments: PathSegment[] = []
    let pos = 0

    for (const seg of verifiedSegments) {
        if (pos < seg.nameStart) {
            segments.push({ text: displayPath.slice(pos, seg.nameStart), color: "path" })
        }
        segments.push({ text: displayPath.slice(seg.nameStart, seg.nameEnd), color: "branch" })
        pos = seg.nameEnd
    }

    if (pos < displayPath.length) {
        segments.push({ text: displayPath.slice(pos), color: "path" })
    }

    const lastVerified = verifiedSegments[verifiedSegments.length - 1]
    const innermostIsWorktree =
        lastVerified &&
        resolvedBranch &&
        normalized.slice(lastVerified.nameStart, lastVerified.nameEnd) === resolvedBranch &&
        (normalized.length === lastVerified.nameEnd || normalized[lastVerified.nameEnd] === "/")

    if (!innermostIsWorktree && resolvedBranch) {
        segments.push({ text: ` (${resolvedBranch})`, color: "branch" })
    }

    return segments
}
