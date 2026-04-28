# pathline

Git-aware path display with worktree highlighting.

A shared library that provides git-aware path display logic for shell prompts
and terminal UI status lines. It highlights worktree folder names when they
match the git branch, supports arbitrary nesting depth, and handles submodules.

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

## Example Output

Regular repository:

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

## Implementations

### TypeScript (`src/pathline.ts`)

Returns an array of `PathSegment` objects with `text` and `color` fields.
The `color` field is `"path"`, `"branch"`, or `"reset"` — the caller maps
these to actual ANSI codes or UI styles.

```typescript
import { buildPathline } from "./src/pathline.js"

const segments = buildPathline(
    "~/git/project/.worktrees/feature/auth",
    "/home/user/git/project/.worktrees/feature/auth",
    "feature/auth",
)
// [
//     { text: "~/git/project/.worktrees/", color: "path" },
//     { text: "feature/auth", color: "branch" },
// ]
```

When the branch does not match the worktree folder:

```typescript
const segments = buildPathline(
    "~/git/project/.worktrees/old-name",
    "/home/user/git/project/.worktrees/old-name",
    "bugfix/renamed",
)
// [
//     { text: "~/git/project/.worktrees/old-name", color: "path" },
//     { text: " (bugfix/renamed)", color: "branch" },
// ]
```

### Shell (`src/pathline.sh`)

Compatible with bash and zsh. Source the file and call `pathline_render`
to output ANSI-colored text. Colors are configurable via environment
variables.

```bash
source /path/to/pathline/src/pathline.sh
pathline_render  # outputs colored path with worktree highlighting
```

Configure colors (hex values for truecolor terminals):

```bash
export PATHLINE_PATH_COLOR="cbd4fe"
export PATHLINE_BRANCH_COLOR="b4a7d6"
```
