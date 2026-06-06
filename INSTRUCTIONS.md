# DeliMap — Agent Instructions (STRICT — Must Follow Without Exception)

> These are binding rules for any AI agent working on this project. Violating these rules is NOT acceptable under any circumstances.
>
> **Workspace:** `/Users/manumathew/Documents/VS_code/DeliMap - the delivery route tracker`
> All project files must be created and modified within this directory ONLY.

---

## Rule 0 — Workspace Location

All code, assets, config files, and project files for DeliMap MUST be created inside:

```
/Users/manumathew/Documents/VS_code/DeliMap - the delivery route tracker/
```

Never write project files to `/tmp`, `.gemini`, or any other directory outside of this workspace.

---

## Rule 1 — Read Before You Think

**At the start of EVERY session, EVERY prompt, and before ANY code or design decision:**

1. Read `GOAL.md` in the workspace root — in full.
2. Read `IMPLEMENTATION_PLAN.md` in the workspace root — in full.
3. Only then proceed with the task.

If these files cannot be found at the workspace location, STOP and inform the user immediately. Do not proceed.

---

## Rule 2 — No Scope Creep

- Every feature implemented MUST map to a checklist item in `IMPLEMENTATION_PLAN.md`.
- Every checklist item MUST map to a feature listed in `GOAL.md`.
- If a new feature or idea arises:
  1. Propose it to the user explicitly.
  2. Wait for user approval.
  3. ONLY THEN update `GOAL.md` and `IMPLEMENTATION_PLAN.md`.
  4. ONLY THEN implement it.

**Never add "nice to have" features silently. Never implement anything not in the plan.**

---

## Rule 3 — Keep Documentation in Sync

After completing any implementation task:
1. Mark the item `[x]` in `IMPLEMENTATION_PLAN.md`.
2. If a new sub-task was discovered, add it as `[ ]`.
3. If a new open decision was found, add it to the Open Decisions table.
4. If understanding of the project changed, update `GOAL.md`.

Documentation must always reflect the real current state of the project.

---

## Rule 4 — Confirm Before Deciding

For any item marked `❓ Pending` in `IMPLEMENTATION_PLAN.md` Open Decisions:
- Do NOT assume and proceed.
- Present the decision to the user and wait for their input.
- Only proceed after confirmed and recorded.

---

## Rule 5 — Minimalism Principle

The user has explicitly requested a **minimalistic but professional** app.

- Do NOT add UI elements, screens, or features not required.
- Do NOT make UI complex for its own sake.
- Every screen serves a clear, single purpose.
- When in doubt: less is more.

---

## Rule 6 — Phase Discipline

- Do NOT skip phases in `IMPLEMENTATION_PLAN.md`.
- Do NOT begin a phase before its **completion criteria** are met.
- If a phase is blocked, record the blocker and inform the user.

---

## Rule 7 — Source of Truth

- `INSTRUCTIONS.md`, `GOAL.md`, and `IMPLEMENTATION_PLAN.md` are the **source of truth**.
- If a chat instruction conflicts with these files, flag the conflict and ask for clarification. Do not silently override.
- These files take precedence over general agent behavior or defaults.

---

*Last updated: 2026-06-05 | Version: 1.1 — Workspace path confirmed*
