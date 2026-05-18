---
mode: agent
description: Run the Phase 0.a spike — decide Path A (extend Unified AI Wildcard API) vs Path B (dedicated /anthropic API).
---

# Phase 0 — API Surface Spike

Goal: decide between **Path A** (extend the existing Unified AI Wildcard API in `citadel-v1` to cover Anthropic) vs **Path B** (stand up a dedicated `/anthropic` API alongside it).

## Inputs to gather
- Read the Unified AI Wildcard API definition under `bicep/infra/modules/apim/apis/` on `citadel-v1`.
- List the policy fragments it already composes (`frag-aad-auth`, `frag-ai-usage`, `frag-openai-usage-streaming`).
- Identify the request/response transformation it does for OpenAI today.

## Decision matrix (fill in, do not skip)
| Criterion | Path A — extend Unified | Path B — dedicated `/anthropic` |
|-----------|-------------------------|----------------------------------|
| Effort to add `POST /v1/messages` |  |  |
| Risk of regressing OpenAI behavior |  |  |
| SSE/streaming policy reuse |  |  |
| Usage-emission schema reuse |  |  |
| Future multi-provider parity |  |  |
| Reversibility |  |  |

## Output
1. Append a **decision row** to the Adjustments table in the plan: which path, with one-line rationale.
2. If Path A: list the exact files in the Unified API definition that need edits.
3. If Path B: propose the new API's folder name and the fragments it composes.
4. Open a sub-task list for Phase 0.b implementation.

Use the **citadel-architect** chat mode for the decision; delegate file inspection to **apim-policy-author**.
