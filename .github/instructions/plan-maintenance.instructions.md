---
description: Discipline for editing the canonical Citadel plan.
applyTo: ".github/prompts/plan-citadelBudgets.prompt.md"
---

# Plan-maintenance rules

- The plan is the source of truth. Code must follow it, not the other way around.
- **Never silently rewrite** locked decisions D1–D6 or the phase numbering.
- Any override of earlier plan text gets a new row in the "🏰 Adjustments from the previous draft" table — old framing vs new framing, with rationale.
- Use the [`update-plan`](../prompts/update-plan.prompt.md) prompt for non-trivial edits.
- Every upstream link must point to the `citadel-v1` branch of `Azure-Samples/ai-hub-gateway-solution-accelerator`. Never link to `main`.
- Inline Bicep examples are **illustrative**; mark them so. Production code lives in `bicep/infra/`.
- Tables > prose for comparisons. Keep TL;DR ≤ 6 lines.
- Out-of-scope items stay out of scope unless a decision row promotes them. Current POC excludes: Power App admin UI, Fabric migration, cost-based budgets, multi-region Cosmos DR, audit-log container.
