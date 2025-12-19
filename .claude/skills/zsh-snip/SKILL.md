---
name: zsh-snip-snippets
description: Create and manage zsh-snip snippets. Use when the user asks to create, modify, or manage shell command snippets for the zsh-snip plugin.
---

# zsh-snip Snippet Creation

## File Format

Every snippet is a plain text file with a metadata header followed by shell content:

```
# name: <path/filename>
# description: <one-line description>
# args: <argument hints>
# created: <ISO 8601 timestamp>
# ---
<shell content>
```

### Header Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Path relative to snippets directory. Controls filename. |
| `description` | Yes | Brief description shown in fzf list. Can be empty. |
| `args` | No | Argument hints for ctrl-x prompt (e.g., `<domain> [port]`). |
| `created` | Yes | ISO 8601 timestamp (e.g., `2025-12-18T09:47:08+00:00`). |

**Important:** The `# ---` separator line is mandatory between headers and content.

### Args Header

The `args:` field controls behavior when executing with ctrl-x:
- **Present:** User is prompted with the hint text before execution
- **Absent:** Snippet executes immediately without prompting

Use angle brackets `<required>` and square brackets `[optional]` in hints:
```
# args: <domain>
# args: <source> <destination>
# args: <name> [--force]
# args: [commit message]
```

## Storage Locations

### User Snippets
```
${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snip/
```

### Project-Local Snippets
```
.zsh-snip/   (in project root, or custom path via ZSH_SNIP_LOCAL_PATH)
```

## Naming Conventions

The `name` field determines the file path. Subdirectories are created automatically.

```
# name: docker/cleanup           -> docker/cleanup
# name: git/sync                 -> git/sync
# name: check-ssl-certificate    -> check-ssl-certificate
# name: aws/s3/sync-bucket       -> aws/s3/sync-bucket
```

**Naming guidelines:**
- Use lowercase with hyphens for multi-word names
- Group related snippets in directories (e.g., `docker/`, `git/`, `k8s/`)
- Keep names short but descriptive

## Content Patterns

### Simple Commands
```zsh
# name: docker/ps-size
# description: Show containers with virtual size
# created: 2025-12-18T09:00:00+00:00
# ---
docker ps --size
```

### Commands with Arguments
Access arguments via `$1`, `$2`, `$@`, `$*`:

```zsh
# name: check-port
# description: Check if a port is open on a host
# args: <host> <port>
# created: 2025-12-18T09:00:00+00:00
# ---
nc -zv "$1" "$2"
```

### Optional Arguments with Defaults
```zsh
# name: git-sync
# description: Add, commit, pull, and push
# args: [commit message]
# created: 2025-12-18T09:00:00+00:00
# ---
git add . && \
git commit -m "${*:-Updated files}" && \
git pull --rebase && \
git push
```

### Multi-Line with Heredoc
```zsh
# name: templates/dockerfile-node
# description: Create a basic Node.js Dockerfile
# created: 2025-12-18T09:00:00+00:00
# ---
cat <<'EOF' > Dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
EOF
```

### Scripts with Validation
```zsh
# name: backup-db
# description: Backup a PostgreSQL database
# args: <database> [output-file]
# created: 2025-12-18T09:00:00+00:00
# ---
local db="$1"
local output="${2:-${db}_$(date +%Y%m%d_%H%M%S).sql.gz}"

if [[ -z "$db" ]]; then
  echo "Usage: backup-db <database> [output-file]"
  return 1
fi

pg_dump "$db" | gzip > "$output"
echo "Backed up $db to $output"
```

### Interactive with Environment Variables
```zsh
# name: docker/transfer-image
# description: Transfer docker image via SSH
# args: <image:tag> <user@host>
# created: 2025-12-18T09:00:00+00:00
# ---
local tag="$1"
local target="$2"
docker image save "$tag" | gzip | ssh "$target" "gunzip -c | docker load"
```

## Creating Snippets

### Using the Write Tool
Write directly to the storage location:

```zsh
# Global snippet
/home/user/.local/share/zsh-snip/<name>

# Project-local snippet
/path/to/project/.zsh-snip/<name>
```

### Timestamp Generation
Always use current UTC time in ISO 8601 format:
```
2025-12-18T14:30:00+00:00
```

## Common Categories

Explore the existing snippets to find what categories exist and to determine if it fits an existing subdirectory.

## Best Practices

1. **Keep snippets focused** - One task per snippet
2. **Use descriptive names** - `docker/prune-all` not `docker/clean`
3. **Validate inputs** - Check required args before executing
4. **Use `local` for variables** - Prevent polluting global scope
5. **Quote variables** - Always quote `"$var"` to handle spaces
6. **Provide usage hints** - Show usage on missing required args
7. **Use `return` not `exit`** - Snippets run in current shell context

## Shell Context

Snippets execute in the current zsh session:
- They have access to all shell functions and aliases
- Environment variables are available
- Changes to `$PWD`, exports, etc. persist after execution
- Use `return` (not `exit`) to abort early
