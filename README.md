# pathline

Git-aware path display with worktree highlighting.

A shared library that provides git-aware path display logic for shell prompts
and terminal UI status lines. It highlights worktree folder names when they
match the git branch, supports arbitrary nesting depth, and handles submodules.
Implementations are provided in TypeScript, shell (bash/zsh), and PowerShell.

## Features

- Detects `.worktrees/<name>` segments in paths and verifies them against the
  actual git branch (case-sensitive)
- Supports branch names with slashes (e.g. `feature/auth` creates
  `.worktrees/feature/auth/`)
- Handles arbitrary nesting (worktrees inside submodules inside worktrees)
- Only highlights verified worktree names (folder name must match branch)
- Omits the branch suffix when the innermost branch is already visible as a
  worktree name
- Works on macOS, Linux, and Windows

## Colors

Default colors are blue for paths and yellow for branches. All implementations
support overriding the defaults:

- **TypeScript** returns a baked ANSI string by default via `buildPathline()`.
  Pass a `PathlineColors` object to override. Use `buildPathlineSegments()` for
  raw segment arrays when custom rendering is needed.
- **Shell** uses env vars `PATHLINE_PATH_COLOR` and `PATHLINE_BRANCH_COLOR`
  (hex values for truecolor terminals, defaults: `cbd4fe` / `b4a7d6`).
- **PowerShell** uses `-PathColor` and `-BranchColor` parameters on
  `Invoke-Pathline`, falling back to `PATHLINE_PATH_COLOR` /
  `PATHLINE_BRANCH_COLOR` env vars, then the same hex defaults.

## Output

Regular repository (branch shown in parentheses):

```
~/git/project (main)
^^^^^^^^^^^^^^        path color
               ^^^^^^ branch color
```

Worktree root (branch matches folder name, so branch is omitted):

```
macOS/Linux:  ~/git/project/.worktrees/feature/auth
Windows:      C:\Users\user\git\project\.worktrees\feature\auth
                                       ^^^^^^^^^^^^
                                       highlighted in branch color
```

Worktree with subdirectory:

```
~/git/project/.worktrees/feature/auth/src/components
                         ^^^^^^^^^^^^
                         highlighted in branch color
```

Inside a submodule within a worktree (outer worktree highlighted, inner
branch shown separately):

```
~/git/project/.worktrees/feature/auth/submod (3f914c9)
                         ^^^^^^^^^^^^        ^^^^^^^^^
                         branch color        detached HEAD of submodule
```

Nested worktrees at arbitrary depth (all matching names highlighted):

```
/tmp/repo/.worktrees/feature/level0/nested/.worktrees/bugfix/level1
                     ^^^^^^^^^^^^^^                   ^^^^^^^^^^^^
                     both highlighted in branch color
```

Home directory without a git repo:

```
macOS:    /Users/username
Linux:    /home/username
Windows:  C:\Users\username
          shown in path color, no branch
```

Worktree where the folder name does not match the branch (no highlighting,
branch shown normally):

```
~/git/project/.worktrees/old-name (bugfix/renamed)
```
