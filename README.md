# pathline

Git-aware path display with worktree highlighting.

A shared library that provides git-aware path display logic for shell prompts and terminal UI status lines. It highlights worktree folder names when they match the git branch, supports arbitrary nesting depth, and handles submodules.

## Features

- Detects `.worktrees/<name>` segments in paths and verifies them against the actual git branch
- Supports branch names with slashes (e.g. `feature/auth` creates `.worktrees/feature/auth/`)
- Handles arbitrary nesting (worktrees inside submodules inside worktrees)
- Only highlights verified worktree names (where the folder name matches the branch)
- Omits the branch suffix when the innermost repo's branch is already visible as a worktree name

## Example Output

```
~/git/project/.worktrees/feature/auth
                         ^^^^^^^^^^^^  (highlighted, branch omitted)

~/git/project/.worktrees/feature/auth/packages/sub
                         ^^^^^^^^^^^^              (highlighted)
                                                   (sub-branch) shown if different

~/git/project (main)
              ^^^^^^  (branch shown when no worktree match)
```

## Implementations

### TypeScript (`src/pathline.ts`)

Standalone function that takes a display path, raw filesystem path, and current branch. Returns an array of colored segments suitable for terminal output.

```ts
import { buildPathline } from './src/pathline.js'

const segments = buildPathline('~/git/project/.worktrees/feature/auth', '/home/user/git/project/.worktrees/feature/auth', 'feature/auth')
// segments: [{ text: '~/git/project/.worktrees/', color: 'blue' }, { text: 'feature/auth', color: 'yellow' }]
```

### Shell (`src/pathline.sh`)

Zsh function that can be sourced into a prompt. Outputs the path with ANSI color codes.

```sh
source /path/to/pathline/src/pathline.sh
pathline_render  # outputs colored path with worktree highlighting
```
