# d — Docker utility

A small shell script that makes common Docker operations fast by letting you
match containers by **name pattern** instead of having to type or copy full
container IDs.

## Installation

```bash
./install.sh           # symlinks d into /usr/local/bin (default)
./install.sh ~/bin     # or choose your own directory on $PATH
```

Or manually:

```bash
cp d /usr/local/bin/d
chmod +x /usr/local/bin/d
```

[fzf](https://github.com/junegunn/fzf) is recommended for the interactive
container selector but not required — a built-in arrow-key menu is used as a
fallback.

```bash
brew install fzf   # macOS
```

## Usage

```
d <command> [pattern] [args...]
```

### Commands

| Command | Pattern | Behaviour |
|---------|---------|-----------|
| `ps [pattern]` | optional | List running containers, filtered if pattern given |
| `psa [pattern]` | optional | List **all** containers (including stopped) |
| `logs <pattern>` | single-select | `docker logs -f` for the matched container |
| `shell <pattern>` | single-select | Open `bash` (or `sh`) in the matched container |
| `exec <pattern> <cmd...>` | single-select | Run a command in the matched container |
| `env <pattern>` | single-select | Print environment variables of the container |
| `inspect <pattern>` | single-select | `docker inspect` the matched container |
| `stop <pattern>` | **all matches** | Stop every container matching the pattern |
| `kill <pattern>` | **all matches** | Kill every container matching the pattern |
| `rm <pattern>` | **all matches** | Force-remove every container matching (running or stopped) |
| `restart <pattern>` | **all matches** | Restart every container matching the pattern |
| `stats [pattern]` | optional | Live `docker stats`, filtered if pattern given |

### Pattern matching

Patterns are **case-insensitive substrings** matched against container name
and image name (via `grep -i`).

### Single-select vs. all-match

- **Single-select commands** (`logs`, `shell`, `exec`, `env`, `inspect`):
  - 1 match → runs immediately
  - Multiple matches → interactive selector (arrow keys + Enter, or fzf)
  - 0 matches → error

- **All-match commands** (`stop`, `kill`, `rm`, `restart`):
  - Operates on **every** container matching the pattern
  - Lists affected containers before acting

## Examples

```bash
# Follow logs for the container whose name contains "api"
d logs api

# Follow logs — interactive picker when multiple match
d logs worker

# Open a shell in the postgres container
d shell postgres

# Run a one-off command
d exec worker env | grep DATABASE

# Kill all containers from a feature branch stack
d kill feature-123

# Stop everything matching "redis"
d stop redis

# Remove all stopped containers matching "tmp"
d rm tmp

# See all running containers
d ps

# Filter the list
d ps web

# Live stats for all containers matching "java"
d stats java
```

## Tips

- Install `fzf` for the best multi-match experience — it supports fuzzy
  search within the picker.
- The `shell` command tries `bash` first and falls back to `sh`.
- `rm` searches **all** containers (not just running ones) so you can clean
  up stopped containers by pattern.
