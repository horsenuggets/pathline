import { describe, it, expect, vi, beforeEach } from "vitest"
import type { PathSegment } from "../src/pathline"

vi.mock("node:child_process", () => ({
    execSync: vi.fn(),
}))

vi.mock("node:fs", () => ({
    existsSync: vi.fn(),
}))

import { execSync } from "node:child_process"
import { existsSync } from "node:fs"
import { buildPathline } from "../src/pathline"

const mockExecSync = execSync as unknown as ReturnType<typeof vi.fn>
const mockExistsSync = existsSync as unknown as ReturnType<typeof vi.fn>

function segmentsToText(segments: PathSegment[]): string {
    return segments.map((s) => s.text).join("")
}

function segmentColors(segments: PathSegment[]): Array<"path" | "branch"> {
    return segments.map((s) => s.color)
}

beforeEach(() => {
    vi.resetAllMocks()
    process.env.HOME = "/home/user"
    delete process.env.USERPROFILE
})

describe("buildPathline", () => {
    it("normal repo path shows branch in parens", () => {
        const result = buildPathline("/home/user/projects/myapp", "main")
        expect(segmentsToText(result)).toBe("~/projects/myapp (main)")
        expect(segmentColors(result)).toEqual(["path", "branch"])
    })

    it("no git repo shows just the path", () => {
        const result = buildPathline("/home/user/documents", undefined)
        expect(segmentsToText(result)).toBe("~/documents")
        expect(segmentColors(result)).toEqual(["path"])
    })

    it("worktree where branch matches folder highlights name, no parens", () => {
        mockExistsSync.mockImplementation((p: string) => {
            return p === "/home/user/repo/.worktrees/feature/auth/.git"
        })
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathline("/home/user/repo/.worktrees/feature/auth", "feature/auth")
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("feature/auth")
        // No parens when worktree matches branch
        expect(segmentsToText(result)).not.toContain("(")
    })

    it("worktree where branch does not match shows full path + branch in parens", () => {
        mockExistsSync.mockImplementation((p: string) => {
            return p === "/home/user/repo/.worktrees/feature/auth/.git"
        })
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathline("/home/user/repo/.worktrees/feature/auth", "bugfix/other")
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth (bugfix/other)")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments.length).toBeGreaterThanOrEqual(2) // highlighted name + parens
    })

    it("nested worktrees (2+ levels) highlight all matching names", () => {
        mockExistsSync.mockImplementation((p: string) => {
            if (p === "/home/user/repo/.worktrees/feature/outer/.git") return true
            if (p === "/home/user/repo/.worktrees/feature/outer/sub/.worktrees/fix/inner/.git") return true
            return false
        })
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/outer") {
                return Buffer.from("feature/outer\n")
            }
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/outer/sub/.worktrees/fix/inner") {
                return Buffer.from("fix/inner\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathline(
            "/home/user/repo/.worktrees/feature/outer/sub/.worktrees/fix/inner",
            "fix/inner",
        )
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments.length).toBeGreaterThanOrEqual(2)
        expect(branchSegments[0].text).toBe("feature/outer")
        expect(branchSegments[1].text).toBe("fix/inner")
    })

    it("subdirectory inside worktree highlights name, remainder in path color", () => {
        mockExistsSync.mockImplementation((p: string) => {
            return p === "/home/user/repo/.worktrees/feature/auth/.git"
        })
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathline(
            "/home/user/repo/.worktrees/feature/auth/src/components",
            "feature/auth",
        )
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth/src/components")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("feature/auth")
        // Remainder after worktree name is path color
        const lastSegment = result[result.length - 1]
        expect(lastSegment.text).toBe("/src/components")
        expect(lastSegment.color).toBe("path")
    })

    it("submodule inside worktree shows outer worktree highlighted + inner branch in parens", () => {
        mockExistsSync.mockImplementation((p: string) => {
            return p === "/home/user/repo/.worktrees/feature/auth/.git"
        })
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        // The innermost branch is different (submodule has its own branch)
        const result = buildPathline(
            "/home/user/repo/.worktrees/feature/auth/libs/shared",
            "develop",
        )
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth/libs/shared (develop)")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments.length).toBeGreaterThanOrEqual(2)
        expect(branchSegments[0].text).toBe("feature/auth")
        expect(branchSegments[1].text).toBe(" (develop)")
    })

    it("Windows paths with backslashes are handled correctly", () => {
        process.env.HOME = ""
        process.env.USERPROFILE = "C:\\Users\\dev"

        mockExistsSync.mockImplementation((p: string) => {
            return p === "C:/Users/dev/repo/.worktrees/feature/auth/.git"
        })
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "C:/Users/dev/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathline(
            "C:\\Users\\dev\\repo\\.worktrees\\feature\\auth",
            "feature/auth",
        )
        // Backslashes normalized, home substituted with ~
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("feature/auth")
    })

    it("home directory substitution with ~", () => {
        const result = buildPathline("/home/user/projects/foo", "main")
        expect(segmentsToText(result)).toMatch(/^~\//)
        expect(segmentsToText(result)).not.toContain("/home/user")
    })

    it("path outside home directory is shown as-is", () => {
        const result = buildPathline("/opt/projects/foo", "main")
        expect(segmentsToText(result)).toBe("/opt/projects/foo (main)")
    })

    it("uses process.cwd() when rawPath is omitted", () => {
        const originalCwd = process.cwd
        process.cwd = () => "/home/user/test-dir"
        try {
            const result = buildPathline(undefined, "main")
            expect(segmentsToText(result)).toBe("~/test-dir (main)")
        } finally {
            process.cwd = originalCwd
        }
    })
})
