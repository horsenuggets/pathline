/*

pathline

Git-aware path display with worktree highlighting. Detects worktrees
by checking for .git FILES (not directories) at path prefixes,
verifies each against its repo's branch (case-sensitive), and returns
colored segments for terminal rendering. Supports arbitrary nesting,
and grays out path segments that no longer exist on disk, such as when
the shell is still sitting in a deleted directory.

*/

import { execSync } from "node:child_process"
import { existsSync, statSync } from "node:fs"

export interface PathSegment {
    text: string
    color: "path" | "branch" | "missing"
}

const DEFAULT_PATH_COLOR = "\x1b[0;34m"
const DEFAULT_BRANCH_COLOR = "\x1b[0;33m"
const DEFAULT_MISSING_COLOR = "\x1b[0;90m"
const RESET = "\x1b[0m"

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
    const home = (process.env.HOME || process.env.USERPROFILE || "").replace(/\\/g, "/")
    if (home && (rawPath === home || rawPath.startsWith(home + "/"))) {
        return "~" + rawPath.slice(home.length)
    }
    return rawPath
}

/**
 * Check if a path has a .git FILE (not directory), indicating a worktree.
 */
function isWorktreeRoot(path: string): boolean {
    const gitPath = path + "/.git"
    if (!existsSync(gitPath)) return false
    try {
        const stat = statSync(gitPath)
        return stat.isFile()
    } catch {
        return false
    }
}

/**
 * Walk path prefixes to find worktree roots. For each prefix where .git
 * is a file (not directory), get the git branch and check if trailing
 * segments match the branch name (case-sensitive). Returns character
 * positions in the display path for highlighting.
 */
function findWorktreeHighlights(
    displayPath: string,
    rawPath: string,
): Array<{ nameStart: number; nameEnd: number }> {
    const normalized = displayPath.replace(/\\/g, "/")
    const segments = normalized.split("/")
    const rawOffset = rawPath.length - displayPath.length
    const results: Array<{ nameStart: number; nameEnd: number }> = []

    // Build prefixes segment by segment
    for (let i = 1; i <= segments.length; i++) {
        const prefix = segments.slice(0, i).join("/")
        const rawPrefix = rawPath.slice(0, prefix.length + rawOffset)

        if (!isWorktreeRoot(rawPrefix)) continue

        const branch = getGitBranch(rawPrefix)
        if (!branch) continue

        // Check if trailing segments of the prefix match the branch
        const branchParts = branch.split("/")
        const branchPartCount = branchParts.length

        if (branchPartCount > i) continue

        const trailingSegments = segments.slice(i - branchPartCount, i)
        const trailing = trailingSegments.join("/")

        if (trailing === branch) {
            // Calculate character positions in the display path
            const beforeTrailing = segments.slice(0, i - branchPartCount).join("/")
            const nameStart = beforeTrailing.length > 0 ? beforeTrailing.length + 1 : 0
            const nameEnd = nameStart + trailing.length
            results.push({ nameStart, nameEnd })
        }
    }

    return results
}

/**
 * Find the character position in the display path where it stops existing on
 * disk. Returns -1 when every segment exists. A shell can stay inside a
 * directory after it is deleted, so the stale part of the path is grayed out.
 */
function findMissingStart(displayPath: string, rawPath: string): number {
    const normalized = displayPath.replace(/\\/g, "/")
    const segments = normalized.split("/")
    const rawOffset = rawPath.length - displayPath.length
    const isUncPath = rawPath.startsWith("//")
    let lastExistingEnd = 0

    for (let i = 1; i <= segments.length; i++) {
        const prefix = segments.slice(0, i).join("/")
        const rawPrefix = rawPath.slice(0, prefix.length + rawOffset)

        // A UNC path is only a valid directory from its complete server/share root,
        // so the incomplete prefixes before it always count as existing.
        if (isUncPath && !/^\/\/[^/]+\/[^/]+/.test(rawPrefix)) {
            lastExistingEnd = prefix.length
            continue
        }

        // An empty prefix is the filesystem root, which always exists.
        if (rawPrefix && !existsSync(rawPrefix)) {
            return lastExistingEnd === 0 ? 0 : lastExistingEnd + 1
        }

        lastExistingEnd = prefix.length
    }

    return -1
}

/**
 * Mark every segment at or after missingStart as missing, splitting the
 * segment that straddles the boundary.
 */
function applyMissingColor(segments: PathSegment[], missingStart: number): PathSegment[] {
    if (missingStart < 0) return segments

    const result: PathSegment[] = []
    let pos = 0

    for (const segment of segments) {
        const end = pos + segment.text.length
        if (end <= missingStart) {
            result.push(segment)
        } else if (pos >= missingStart) {
            result.push({ text: segment.text, color: "missing" })
        } else {
            result.push({ text: segment.text.slice(0, missingStart - pos), color: segment.color })
            result.push({ text: segment.text.slice(missingStart - pos), color: "missing" })
        }
        pos = end
    }

    return result
}

/**
 * Build a pathline from a raw filesystem path. Returns a baked ANSI string
 * ready to print, with path segments in blue and branch segments in yellow.
 *
 * The home directory prefix is automatically replaced with ~ for display.
 * If branch is not provided, it is computed via git.
 *
 * @param rawPath - The actual filesystem path (default: process.cwd())
 * @param branch - The innermost git branch (computed if omitted)
 * @param pathColor - ANSI escape for path segments (default: blue)
 * @param branchColor - ANSI escape for branch segments (default: yellow)
 * @param missingColor - ANSI escape for missing segments (default: gray)
 */
export function buildPathline(
    rawPath?: string,
    branch?: string,
    pathColor?: string,
    branchColor?: string,
    missingColor?: string,
): string {
    const segments = buildPathlineSegments(rawPath, branch)
    const resolvedPath = pathColor ?? DEFAULT_PATH_COLOR
    const resolvedBranch = branchColor ?? DEFAULT_BRANCH_COLOR
    const resolvedMissing = missingColor ?? DEFAULT_MISSING_COLOR

    let result = ""
    for (const seg of segments) {
        let color = resolvedPath
        if (seg.color === "branch") color = resolvedBranch
        else if (seg.color === "missing") color = resolvedMissing
        result += color + seg.text
    }
    result += RESET

    return result
}

/**
 * Build a pathline from a raw filesystem path. Returns an array of colored
 * segments representing a git-aware path display with worktree highlighting.
 *
 * The home directory prefix is automatically replaced with ~ for display.
 * If branch is not provided, it is computed via git.
 *
 * @param rawPath - The actual filesystem path (default: process.cwd())
 * @param branch - The innermost git branch (computed if omitted)
 */
export function buildPathlineSegments(rawPath?: string, branch?: string): PathSegment[] {
    rawPath = rawPath ?? process.cwd()
    const normalizedRaw = rawPath.replace(/\\/g, "/")
    let displayPath = toDisplayPath(normalizedRaw)
    const resolvedBranch = branch ?? getGitBranch(rawPath)
    const verifiedSegments = findWorktreeHighlights(displayPath, normalizedRaw)
    const missingStart = findMissingStart(displayPath, normalizedRaw)

    // Directories always end with a slash. Add it after finding highlights, so that the
    // path splits into the same segments as before.
    if (!displayPath.endsWith("/")) displayPath += "/"

    const segments = applyMissingColor(
        buildHighlightedSegments(displayPath, verifiedSegments),
        missingStart,
    )

    const lastVerified = verifiedSegments[verifiedSegments.length - 1]
    const innermostIsWorktree =
        lastVerified &&
        resolvedBranch &&
        displayPath.slice(lastVerified.nameStart, lastVerified.nameEnd) === resolvedBranch &&
        displayPath[lastVerified.nameEnd] === "/"

    if (!innermostIsWorktree && resolvedBranch) {
        segments.push({ text: ` (${resolvedBranch})`, color: "branch" })
    }

    return segments
}

/**
 * Split the display path into path and branch segments based on the verified
 * worktree highlights.
 */
function buildHighlightedSegments(
    displayPath: string,
    verifiedSegments: Array<{ nameStart: number; nameEnd: number }>,
): PathSegment[] {
    if (verifiedSegments.length === 0) {
        return [{ text: displayPath, color: "path" }]
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

    return segments
}
