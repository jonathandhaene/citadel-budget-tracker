---
mode: agent
description: Execute one phase from the Citadel Budgets plan end-to-end via the appropriate squad.
---

# Implement Phase

Phase to implement: **${input:phase:Phase number (0, 1, 2, 3, 4a, 4b, 4c, 4d)}**

## Procedure
1. **Scope.** Read the named phase section in [plan-citadelBudgets.prompt.md](plan-citadelBudgets.prompt.md). Print a one-paragraph scope summary citing the phase header.
2. **Squad.** Look up the squad for this phase in [.github/squads.md](../squads.md). State which specialist agents you'll use.
3. **Decompose.** Create a todo list with one item per concrete artifact (file, fragment, container, notebook cell).
4. **Execute.** For each todo:
   - Switch into the right specialist mode mentally (apply its rules — see `.github/chatmodes/*.chatmode.md`).
   - Produce the artifact.
   - Verify (bicep build, notebook cell run, plan still scans).
   - Mark the todo complete.
5. **Closeout.** Append a dated note under the phase section in the plan summarizing what shipped. If a locked decision was challenged, route through the [`update-plan`](update-plan.prompt.md) prompt instead.

## Guardrails
- Never silently change D1–D6. If a sub-task pushes against them, stop and surface to citadel-architect.
- All paths under `bicep/infra/` (not `infra/`).
- All upstream references on `citadel-v1`.
- Bicep snippets in plan/docs are illustrative; production Bicep goes to `.bicep` files.
