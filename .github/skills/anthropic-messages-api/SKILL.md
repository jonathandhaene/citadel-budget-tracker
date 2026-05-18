---
description: Anthropic Messages API surface, usage fields, and SSE streaming semantics for Citadel gateway work.
---

# Anthropic Messages API

## Endpoint
- `POST /v1/messages` — primary chat surface used by Claude Code.
- Headers (client-side): `x-api-key` (Anthropic SaaS), `anthropic-version`, `anthropic-beta` (varies). When fronted by APIM+Foundry, the client carries an Entra JWT instead and APIM auths to the backend with its managed identity.

## Request shape (relevant fields only)
```json
{
  "model": "claude-3-7-sonnet-20250219",
  "max_tokens": 1024,
  "stream": true,
  "messages": [...]
}
```

## Non-streaming response — usage fields
```json
{
  "id": "msg_…",
  "model": "claude-3-7-sonnet-20250219",
  "usage": { "input_tokens": 1234, "output_tokens": 567 }
}
```

**Mapping for Citadel Event Hub schema (do not invent new fields):**
| Anthropic | Citadel Event Hub |
|-----------|-------------------|
| `usage.input_tokens` | `promptTokens` |
| `usage.output_tokens` | `responseTokens` |
| sum | `totalTokens` |
| `model` | `model` |
| JWT `oid` | `userId` / `oid` (extended field) |

## Streaming (SSE)
Event sequence:
1. `message_start` — initial `usage.input_tokens` available; `output_tokens` is 0 / partial.
2. `content_block_start` / `content_block_delta` / `content_block_stop` (repeated).
3. `message_delta` — **terminal event carries final `usage.output_tokens`**. This is the one to capture for billing.
4. `message_stop`.

> Citadel rule: capture `output_tokens` from the **terminal `message_delta`**, not earlier deltas. Use the `frag-openai-usage-streaming.xml` pattern as a template.

## Errors
- 4xx with JSON body `{"type":"error","error":{"type":"…","message":"…"}}`. Citadel adds 429 (budget hard-block) with `Retry-After` header.

## Versioning
- `anthropic-version` header pinned by client; APIM should pass through unchanged unless we explicitly normalize.
