---
name: backlog-management
description: Manage the repository task backlog - create tasks, update status, capture ideas, and keep the backlog organized. Use when working with tasks in backlog/.
---

# Backlog Management

## Overview

Manage tasks tracked in `backlog/` within the repository. Tasks are markdown files with structured frontmatter, indexed in `backlog/index.md`.

## Structure

```
backlog/
├── index.md          # Task index with next_id counter
├── tasks/            # Task definition files
│   └── {id}-{slug}.md
└── resources/        # Transient task resources (optional)
    └── {id}-{slug}/         # Grouped by task ID
        ├── spec.md
        ├── readme-draft.md
        └── ...
```

## Index Format (backlog/index.md)

```markdown
---
next_id: 6
---

# Backlog

## Ideas

- Quick capture items without IDs

## Open

- [#5 -- Short description](./tasks/5-slug.md)

## In Progress

- [#3 -- Currently being worked on](./tasks/3-slug.md)

## Closed

- [#2 -- Completed task](./tasks/2-fix-migrations.md)
```

## Task File Format (backlog/tasks/{id}-{slug}.md)

```markdown
---
id: 5
status: open | in_progress | closed
branch: 5-bot-protection
created: 2025-01-15
updated: 2025-01-16
---

# Short descriptive title

## ACs

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

## Spec

Link to resources if needed: [See spec](../resources/5-bot-protection/spec.md)

Or inline specification for simpler tasks.

## Notes

Notes captured during implementation.
```

## Operations

### Capture an Idea

Add a bullet point to the Ideas section in index.md. No ID needed.

### Create a Task

1. Read `backlog/index.md` to get `next_id`
2. Generate slug from title (lowercase, hyphens, ~3-4 words)
3. Create `backlog/tasks/{id}-{slug}.md` with frontmatter
4. Add link to Open section in index.md
5. Increment `next_id` in index.md frontmatter
6. Commit both files atomically

### Start Working on a Task

1. Update task frontmatter: `status: in_progress`, `branch: <branch-name>`, `updated: <today>`
2. Move task link from Open to In Progress in index.md
3. Commit changes

The `branch` field links the task to its implementation branch. Use the task's `{id}-{slug}` as the branch name by default.

### Complete a Task

1. Ensure all ACs are checked in task file
2. Update task frontmatter: `status: closed`, `updated: <today>`
3. Move task link from In Progress to Closed in index.md
4. Commit changes

### Add Notes to a Task

Append to the Notes section in the task file. Include date if relevant.

## ID and Slug Conventions

- **ID**: Sequential integer, never reused
- **Slug**: Derived from title, lowercase, hyphens for spaces
  - "Create sophisticated anti-bot protection" → `bot-protection`
  - "Fix database migrations" → `fix-migrations`
  - Keep slugs short (2-4 words)

## Commit Guidelines

- Commit backlog changes separately from code changes when possible
- Use descriptive messages: `backlog: create #5 bot-protection`
- When completing a task alongside code: `feat: implement X (closes #5)`

## Best Practices

- Keep task descriptions concise - details go in ACs or resources
- Use `resources/{id}-{slug}/` for transient documents: specs, README drafts, research notes
- Resources are working documents - incorporate them into the codebase, then delete
- Update the `updated` field whenever modifying a task
- Check ACs as you complete them during implementation
- Move tasks through statuses promptly - don't let index.md drift
- When the human provides feedback on a task, capture it in `resources/{id}-{slug}/human-feedback.md`
