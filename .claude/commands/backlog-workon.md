---
description: Work on a backlog task until completion
---

# Work on Backlog Task

Use your **backlog-management** skill for backlog structure and operations.

## 1. Load the Task

Task identifier: ${ARGUMENTS}

Find the task in `backlog/tasks/`. If not found, list available tasks from `backlog/index.md` and ask which one to work on.

## 2. Information Check

Before starting, critically assess:

- Is the goal clear and unambiguous?
- Are the acceptance criteria testable?
- Are there technical decisions that need human input?
- Are there unknowns that could block you mid-implementation?

If ANY information is missing: list specific questions and ask the human before proceeding. Do NOT start with unresolved ambiguity.

## 3. Start Work

1. Update task status to `in_progress` (task file + index.md)
2. Commit: `backlog: start #<id> <slug>`
3. Use TodoWrite to break down the work based on ACs

## 4. Implement

- Follow TDD: write tests first, then implement
- Check off ACs as you complete them
- Add notes to the task file for anything noteworthy
- Commit frequently

## 5. Complete

1. Run all tests
2. Update task status to `closed` (task file + index.md)
3. Commit: `backlog: close #<id> <slug>`

## Key Reminders

- **Stop and ask** if you hit unexpected complexity or ambiguity
- **Don't over-engineer** - implement exactly what the ACs require
- **Use TDD** - tests first, then implement
