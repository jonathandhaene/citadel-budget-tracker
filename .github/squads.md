# Squads — agent compositions per workstream

A *squad* is a recurring grouping of chat modes that ship a phase. The **Phase Implementer** is the squad lead; specialists execute.

> Switch a squad in by activating the lead chat mode (`@workspace /mode phase-implementer`) and asking it to run the named phase. The lead picks specialists from this table.

## Squad: Phase 0 — API surface spike
| Role | Chat mode |
|------|-----------|
| Lead | [phase-implementer](chatmodes/phase-implementer.chatmode.md) |
| Architecture gate | [citadel-architect](chatmodes/citadel-architect.chatmode.md) |
| APIM trial fragments | [apim-policy-author](chatmodes/apim-policy-author.chatmode.md) |
| Validation harness | [validation-notebook-author](chatmodes/validation-notebook-author.chatmode.md) |

**Output:** Path A vs Path B decision row in the Adjustments table.

## Squad: Phase 1 — JWT parameterization
| Role | Chat mode |
|------|-----------|
| Lead | phase-implementer |
| Implementer | apim-policy-author |
| Parameter wiring | bicep-iac-author |
| Tests | validation-notebook-author |

## Squad: Phase 2 — Logic App schema extension
| Role | Chat mode |
|------|-----------|
| Lead | phase-implementer |
| Workflow JSON | apim-policy-author *(close enough — owns ingestion-side mapping)* |
| Cosmos shape | cosmos-schema-designer |
| Bicep wiring | bicep-iac-author |

## Squad: Phase 4 — Budget enforcement (a–d)
| Role | Chat mode |
|------|-----------|
| Lead | phase-implementer |
| Cosmos `ai-usage-monthly` / `budgets` / `user-tier` | cosmos-schema-designer |
| Tier-sync Function | bicep-iac-author *(infra)* + (future) function code agent |
| APIM enforcement fragment `frag-citadel-budget.xml` | apim-policy-author |
| Access Contracts seed | bicep-iac-author |
| Enforcement tests | validation-notebook-author |

## Squad: Maintenance — plan refresh
| Role | Chat mode |
|------|-----------|
| Lead | citadel-architect |
| Research | citadel-architect (uses `fetch` / `githubRepo`) |
| Edits | citadel-architect via [`update-plan`](prompts/update-plan.prompt.md) |

## Squad: PR review
| Role | Chat mode |
|------|-----------|
| Lead | citadel-architect |
| Domain check (by file type) | apim-policy-author / bicep-iac-author / cosmos-schema-designer / validation-notebook-author |
| Checklist | [`review-citadel-pr`](prompts/review-citadel-pr.prompt.md) |
