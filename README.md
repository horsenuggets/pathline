# pathline

Git-aware path display with worktree highlighting.

A shared library that provides git-aware path display logic for shell prompts
and terminal UI status lines. It highlights worktree folder names when they
match the git branch, supports arbitrary nesting depth, and handles submodules.
Implementations are provided in TypeScript, shell (bash/zsh), and PowerShell.

## Features

- Detects worktree roots at any path prefix and verifies them against the
  actual git branch (case-sensitive)
- Supports branch names with slashes (e.g. `feature/auth` creates
  `.wt/feature/auth/`)
- Handles arbitrary nesting (worktrees inside submodules inside worktrees)
- Only highlights verified worktree names (folder name must match branch)
- Omits the branch suffix when the innermost branch is already visible as a
  worktree name
- Grays out path segments that no longer exist, such as when the shell is still
  inside a deleted directory
- Works on macOS, Linux, and Windows

## Colors

All implementations take the same five optional positional arguments:

```
buildPathline(rawPath?, branch?, pathColor?, branchColor?, missingColor?)
```

The 3rd through 5th arguments override colors. Defaults are blue/yellow/gray
ANSI escapes in TypeScript (`\x1b[0;34m` / `\x1b[0;33m` / `\x1b[0;90m`) and hex
values in shell/PowerShell (`cbd4fe` / `b4a7d6` / `888888`). The shell version
also accepts ANSI escapes such as `\033[0;34m` in place of hex values, for
terminals without truecolor support. Use `buildPathlineSegments(rawPath?, branch?)`
in TypeScript for raw segment arrays when custom rendering is needed.

## Output

Regular repository (branch shown in parentheses):

Paths always end with a slash to mark them as directories. The root directory is shown
as a single `/`.

```
~/git/project/ (main)
^^^^^^^^^^^^^^^        path color
                ^^^^^^ branch color
```

Worktree root (branch matches folder name, so branch is omitted):

```
macOS/Linux:  ~/git/project/.wt/feature/auth/
Windows:      C:\Users\user\git\project\.wt\feature\auth\
                                ^^^^^^^^^^^^
                                highlighted in branch color
```

Worktree with subdirectory:

```
~/git/project/.wt/feature/auth/src/components/
                  ^^^^^^^^^^^^
                  highlighted in branch color
```

Inside a submodule within a worktree (outer worktree highlighted, inner
branch shown separately):

```
~/git/project/.wt/feature/auth/submod/ (3f914c9)
                  ^^^^^^^^^^^^         ^^^^^^^^^
                  branch color         detached HEAD of submodule
```

Nested worktrees at arbitrary depth (all matching names highlighted):

```
/tmp/repo/.wt/feature/level0/nested/.wt/bugfix/level1/
              ^^^^^^^^^^^^^^            ^^^^^^^^^^^^^^
              both highlighted in branch color
```

Home directory without a git repo:

```
~/
shown in path color, no branch
```

Worktree where the folder name does not match the branch (no highlighting,
branch shown normally):

```
~/git/project/.wt/old-name/ (bugfix/renamed)
```

Deleted directory (the shell is still inside a path that no longer exists, so
the missing part is shown in the missing color):

```
~/git/project/nested/folder/
^^^^^^^^^^^^^^              path color
              ^^^^^^^^^^^^^^ missing color
```

Worktree with a deleted subdirectory (path, branch, and missing colors at
once):

```
~/git/project/.wt/feature/auth/src/gone/
                  ^^^^^^^^^^^^     ^^^^^
                  branch color     missing color
```

## Preview

To see every example above rendered in full color, run the preview script, which
builds temporary repositories and prints each case with the classic ANSI blue and
yellow that terminal prompts typically use...

```bash
npm run preview
```

## Testing

All tests run via vitest:

```bash
npm test
```

TypeScript unit tests run directly. Shell (bash/zsh) and PowerShell tests run
inside Docker containers, so Docker Desktop must be running for the full suite.
