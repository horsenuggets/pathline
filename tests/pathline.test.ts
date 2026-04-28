import { describe, it, expect, vi, beforeEach } from "vitest"
import type { PathSegment } from "../src/pathline"

vi.mock("node:child_process", () => ({
    execSync: vi.fn(),
}))

vi.mock("node:fs", () => ({
    existsSync: vi.fn(),
    statSync: vi.fn(),
}))

import { execSync } from "node:child_process"
import { existsSync, statSync } from "node:fs"
import { buildPathline, buildPathlineSegments } from "../src/pathline"

const mockExecSync = execSync as unknown as ReturnType<typeof vi.fn>
const mockExistsSync = existsSync as unknown as ReturnType<typeof vi.fn>
const mockStatSync = statSync as unknown as ReturnType<typeof vi.fn>

function segmentsToText(segments: PathSegment[]): string {
    return segments.map((s) => s.text).join("")
}

function segmentColors(segments: PathSegment[]): Array<"path" | "branch"> {
    return segments.map((s) => s.color)
}

/** Helper to mock a .git FILE (worktree) at a given path */
function mockWorktreeAt(paths: string[]) {
    mockExistsSync.mockImplementation((p: string) => {
        return paths.includes(p)
    })
    mockStatSync.mockImplementation((p: string) => {
        if (paths.includes(p)) {
            return { isFile: () => true }
        }
        throw new Error("ENOENT")
    })
}

/** Helper to mock a .git DIRECTORY (regular clone) at a given path */
function mockRegularRepoAt(paths: string[]) {
    mockExistsSync.mockImplementation((p: string) => {
        return paths.includes(p)
    })
    mockStatSync.mockImplementation((p: string) => {
        if (paths.includes(p)) {
            return { isFile: () => false }
        }
        throw new Error("ENOENT")
    })
}

beforeEach(() => {
    vi.resetAllMocks()
    process.env.HOME = "/home/user"
    delete process.env.USERPROFILE
})

describe("buildPathline (ANSI string output)", () => {
    it("returns a string with default ANSI color codes", () => {
        const result = buildPathline("/home/user/projects/myapp", "main")
        expect(typeof result).toBe("string")
        expect(result).toContain("\x1b[0;34m")
        expect(result).toContain("\x1b[0;33m")
        expect(result).toContain("\x1b[0m")
    })

    it("default colors produce expected ANSI codes", () => {
        const result = buildPathline("/home/user/projects/myapp", "main")
        // Path in blue
        expect(result).toContain("\x1b[0;34m~/projects/myapp")
        // Branch in yellow
        expect(result).toContain("\x1b[0;33m (main)")
        // Ends with reset
        expect(result.endsWith("\x1b[0m")).toBe(true)
    })

    it("custom colors override defaults", () => {
        const result = buildPathline("/home/user/projects/myapp", "main", {
            path: "\x1b[0;32m",
            branch: "\x1b[0;31m",
            reset: "\x1b[0m",
        })
        expect(result).toContain("\x1b[0;32m~/projects/myapp")
        expect(result).toContain("\x1b[0;31m (main)")
        expect(result).not.toContain("\x1b[0;34m")
        expect(result).not.toContain("\x1b[0;33m")
    })

    it("partial color override only changes specified colors", () => {
        const result = buildPathline("/home/user/projects/myapp", "main", {
            branch: "\x1b[0;35m",
        })
        // Path still uses default blue
        expect(result).toContain("\x1b[0;34m~/projects/myapp")
        // Branch uses custom purple
        expect(result).toContain("\x1b[0;35m (main)")
    })

    it("worktree path produces correct ANSI output", () => {
        mockWorktreeAt(["/home/user/repo/.worktrees/feature/auth/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathline("/home/user/repo/.worktrees/feature/auth", "feature/auth")
        expect(result).toContain("\x1b[0;34m~/repo/.worktrees/")
        expect(result).toContain("\x1b[0;33mfeature/auth")
        expect(result).not.toContain("(feature/auth)")
    })

    it("no branch shows just path color and reset", () => {
        const result = buildPathline("/home/user/documents", undefined)
        expect(result).toBe("\x1b[0;34m~/documents\x1b[0m")
    })
})

describe("buildPathlineSegments (segment array output)", () => {
    it("normal repo path shows branch in parens", () => {
        const result = buildPathlineSegments("/home/user/projects/myapp", "main")
        expect(segmentsToText(result)).toBe("~/projects/myapp (main)")
        expect(segmentColors(result)).toEqual(["path", "branch"])
    })

    it("no git repo shows just the path", () => {
        const result = buildPathlineSegments("/home/user/documents", undefined)
        expect(segmentsToText(result)).toBe("~/documents")
        expect(segmentColors(result)).toEqual(["path"])
    })

    it("regular clone (.git is directory) does NOT highlight", () => {
        mockRegularRepoAt(["/home/user/repo/.git"])
        const result = buildPathlineSegments("/home/user/repo", "main")
        expect(segmentsToText(result)).toBe("~/repo (main)")
        expect(segmentColors(result)).toEqual(["path", "branch"])
    })

    it("worktree where branch matches folder highlights name, no parens", () => {
        mockWorktreeAt(["/home/user/repo/.worktrees/feature/auth/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathlineSegments("/home/user/repo/.worktrees/feature/auth", "feature/auth")
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("feature/auth")
        expect(segmentsToText(result)).not.toContain("(")
    })

    it("worktree NOT in .worktrees/ folder highlights correctly", () => {
        mockWorktreeAt(["/home/user/repos/feature/auth/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repos/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathlineSegments("/home/user/repos/feature/auth", "feature/auth")
        expect(segmentsToText(result)).toBe("~/repos/feature/auth")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("feature/auth")
        expect(segmentsToText(result)).not.toContain("(")
    })

    it("worktree in arbitrary folder highlights correctly", () => {
        mockWorktreeAt(["/tmp/my-worktree/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/tmp/my-worktree") {
                return Buffer.from("my-worktree\n")
            }
            throw new Error("not a git repo")
        })

        process.env.HOME = "/home/user"
        const result = buildPathlineSegments("/tmp/my-worktree", "my-worktree")
        expect(segmentsToText(result)).toBe("/tmp/my-worktree")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("my-worktree")
    })

    it("worktree where branch does not match shows full path + branch in parens", () => {
        mockWorktreeAt(["/home/user/repo/.worktrees/feature/auth/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathlineSegments("/home/user/repo/.worktrees/feature/auth", "bugfix/other")
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
        mockStatSync.mockImplementation((p: string) => {
            if (p === "/home/user/repo/.worktrees/feature/outer/.git") return { isFile: () => true }
            if (p === "/home/user/repo/.worktrees/feature/outer/sub/.worktrees/fix/inner/.git") return { isFile: () => true }
            throw new Error("ENOENT")
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

        const result = buildPathlineSegments(
            "/home/user/repo/.worktrees/feature/outer/sub/.worktrees/fix/inner",
            "fix/inner",
        )
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments.length).toBeGreaterThanOrEqual(2)
        expect(branchSegments[0].text).toBe("feature/outer")
        expect(branchSegments[1].text).toBe("fix/inner")
    })

    it("subdirectory inside worktree highlights name, remainder in path color", () => {
        mockWorktreeAt(["/home/user/repo/.worktrees/feature/auth/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathlineSegments(
            "/home/user/repo/.worktrees/feature/auth/src/components",
            "feature/auth",
        )
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth/src/components")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("feature/auth")
        const lastSegment = result[result.length - 1]
        expect(lastSegment.text).toBe("/src/components")
        expect(lastSegment.color).toBe("path")
    })

    it("submodule inside worktree shows outer worktree highlighted + inner branch in parens", () => {
        mockWorktreeAt(["/home/user/repo/.worktrees/feature/auth/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "/home/user/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathlineSegments(
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

        mockWorktreeAt(["C:/Users/dev/repo/.worktrees/feature/auth/.git"])
        mockExecSync.mockImplementation((cmd: string, opts: { cwd?: string }) => {
            if (opts?.cwd === "C:/Users/dev/repo/.worktrees/feature/auth") {
                return Buffer.from("feature/auth\n")
            }
            throw new Error("not a git repo")
        })

        const result = buildPathlineSegments(
            "C:\\Users\\dev\\repo\\.worktrees\\feature\\auth",
            "feature/auth",
        )
        expect(segmentsToText(result)).toBe("~/repo/.worktrees/feature/auth")
        const branchSegments = result.filter((s) => s.color === "branch")
        expect(branchSegments).toHaveLength(1)
        expect(branchSegments[0].text).toBe("feature/auth")
    })

    it("home directory substitution with ~", () => {
        const result = buildPathlineSegments("/home/user/projects/foo", "main")
        expect(segmentsToText(result)).toMatch(/^~\//)
        expect(segmentsToText(result)).not.toContain("/home/user")
    })

    it("path outside home directory is shown as-is", () => {
        const result = buildPathlineSegments("/opt/projects/foo", "main")
        expect(segmentsToText(result)).toBe("/opt/projects/foo (main)")
    })

    it("uses process.cwd() when rawPath is omitted", () => {
        const originalCwd = process.cwd
        process.cwd = () => "/home/user/test-dir"
        try {
            const result = buildPathlineSegments(undefined, "main")
            expect(segmentsToText(result)).toBe("~/test-dir (main)")
        } finally {
            process.cwd = originalCwd
        }
    })
})
