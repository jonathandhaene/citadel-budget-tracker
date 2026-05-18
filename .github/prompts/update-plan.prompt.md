---
mode: agent
description: Update the canonical Citadel Budgets plan with new findings, decisions, or upstream deltas. Append-by-amendment only.
---

# Update Plan

Amend [.github/prompts/plan-citadelBudgets.prompt.md](plan-citadelBudgets.prompt.md) with the following finding / decision / upstream delta:

**${input:summary:What changed and why (one sentence)?}**

## Procedure
1. Read the plan in full.
2. Classify the change:
   - **Adjustment** (overrides earlier plan text) → add a row to the "🏰 Adjustments from the previous draft" table with the old vs new framing.
   - **New finding** (extends a phase without overriding) → add a dated note under the relevant Phase section.
   - **Decision change** (touches D1–D6) → **STOP**. Locked decisions need an explicit ADR-style amendment. Confirm with the user before proceeding.
3. Preserve phase numbering and decision IDs verbatim.
4. Update the TL;DR only if the headline framing actually changed.
5. Cross-check: every upstream link points to the `citadel-v1` branch (never `main`).
6. Update the Risks section if the change introduces or retires a risk.
7. Print a short diff summary (≤ 5 bullets) for human review before writing.

## Style guardrails
- Tables > prose for comparisons.
- Bicep snippets are illustrative — mark them so.
- No silent rewrites of locked sections.
