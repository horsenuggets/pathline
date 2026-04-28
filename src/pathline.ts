import { execSync } from 'node:child_process'
import { existsSync } from 'node:fs'

export interface PathSegment {
  text: string
  color: 'blue' | 'yellow' | 'reset'
}

/**
 * Get the git branch for a directory, or undefined if not in a git repo.
 */
function getGitBranch(cwd: string): string | undefined {
  try {
    return (
      execSync('git symbolic-ref --short HEAD', {
        cwd,
        stdio: ['pipe', 'pipe', 'pipe'],
        timeout: 2000,
      })
        .toString()
        .trim() || undefined
    )
  } catch {
    try {
      return (
        execSync('git rev-parse --short HEAD', {
          cwd,
          stdio: ['pipe', 'pipe', 'pipe'],
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
 * Find and verify all .worktrees/<name> segments in the path. For each
 * /.worktrees/ marker, probes git to find the worktree root and verifies
 * the folder name matches the branch (case-sensitive). Supports arbitrary
 * nesting depth (worktrees inside submodules inside worktrees, etc.).
 */
export function findVerifiedWorktrees(
  displayPath: string,
  rawPath: string,
): Array<{ nameStart: number; nameEnd: number }> {
  const normalized = displayPath.replace(/\\/g, '/')
  const marker = '/.worktrees/'
  const rawOffset = rawPath.length - displayPath.length
  const results: Array<{ nameStart: number; nameEnd: number }> = []

  let searchFrom = 0
  while (true) {
    const markerIdx = normalized.indexOf(marker, searchFrom)
    if (markerIdx === -1) break

    const nameStart = markerIdx + marker.length
    if (nameStart >= normalized.length) break

    // The worktree name can contain slashes (e.g. "feature/auth").
    // Try progressively longer path segments until we find one that
    // is a git worktree root with a matching branch name.
    const afterMarker = normalized.slice(nameStart)
    const parts = afterMarker.split('/')
    let matched = false

    for (let i = 1; i <= parts.length; i++) {
      const candidateName = parts.slice(0, i).join('/')
      const candidateRawPath = rawPath.slice(0, nameStart + rawOffset + candidateName.length)

      // Only check git branch if this is a worktree root (.git file exists)
      if (!existsSync(candidateRawPath + '/.git')) continue
      const branch = getGitBranch(candidateRawPath)

      if (branch === candidateName) {
        results.push({ nameStart, nameEnd: nameStart + candidateName.length })
        searchFrom = nameStart + candidateName.length
        matched = true
        break
      }

      // If we got a branch but it doesn't match, stop probing
      if (branch) break
    }

    if (!matched) {
      searchFrom = nameStart
    }
  }

  return results
}

/**
 * Build a pathline: an array of colored segments representing a git-aware
 * path display with worktree highlighting.
 *
 * @param displayPath - The path as shown to the user (e.g. with ~ for home)
 * @param rawPath - The actual filesystem path (for git lookups)
 * @param branch - The innermost git branch (or undefined if not in a repo)
 */
export function buildPathline(
  displayPath: string,
  rawPath: string,
  branch: string | undefined,
): PathSegment[] {
  const normalized = displayPath.replace(/\\/g, '/')
  const verifiedSegments = findVerifiedWorktrees(displayPath, rawPath)

  if (verifiedSegments.length === 0) {
    const segments: PathSegment[] = [{ text: displayPath, color: 'blue' }]
    if (branch) {
      segments.push({ text: ` (${branch})`, color: 'yellow' })
    }
    return segments
  }

  // Build path with yellow highlights for verified worktree names
  const segments: PathSegment[] = []
  let pos = 0

  for (const seg of verifiedSegments) {
    if (pos < seg.nameStart) {
      segments.push({ text: displayPath.slice(pos, seg.nameStart), color: 'blue' })
    }
    segments.push({ text: displayPath.slice(seg.nameStart, seg.nameEnd), color: 'yellow' })
    pos = seg.nameEnd
  }

  if (pos < displayPath.length) {
    segments.push({ text: displayPath.slice(pos), color: 'blue' })
  }

  // Show branch in parens if the innermost repo's branch isn't a worktree name
  const lastVerified = verifiedSegments[verifiedSegments.length - 1]
  const innermostIsWorktree =
    lastVerified &&
    branch &&
    normalized.slice(lastVerified.nameStart, lastVerified.nameEnd) === branch &&
    (normalized.length === lastVerified.nameEnd || normalized[lastVerified.nameEnd] === '/')

  if (!innermostIsWorktree && branch) {
    segments.push({ text: ` (${branch})`, color: 'yellow' })
  }

  return segments
}
