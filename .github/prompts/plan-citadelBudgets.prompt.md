# Plan: Citadel Budgets — Per-User Budgets & Reporting for Claude Code on Foundry

## TL;DR
Fork **`Azure-Samples/ai-hub-gateway-solution-accelerator` branch `citadel-v1`** (the reference implementation of Layer 1 — *Governance Hub* — of the [Foundry Citadel Platform](https://github.com/Azure-Samples/foundry-citadel-platform)) into an internal **Citadel Budgets** repo. Add an **Anthropic-compatible surface** in front of Foundry's Anthropic models — first investigate whether the upstream **Unified AI Wildcard API** (new in `citadel-v1`, already covers Azure OpenAI, Foundry and Gemini) can be extended; otherwise add a dedicated `/anthropic` API. Then layer in (1) JWT-based user identity extraction (`citadel-v1` already ships JWT auth + a validation notebook), (2) Anthropic-aware token telemetry with `user_oid`, (3) per-user PBI reporting, and (4) a per-user-per-model budget store with hard-block enforcement at 100% of monthly calendar limit, **expressed as a superset extension of Citadel Access Contracts**. Tier mapping must be done by a server-side sync from Entra → Cosmos because Claude Code's JWT audience is the Anthropic-published app, whose token does **not** carry custom group claims.

## 🏰 Adjustments from the previous draft (anchoring on Citadel Governance Hub)

The earlier draft assumed a fork of `main` on `ai-hub-gateway-solution-accelerator`. After review of the Citadel architecture and the `citadel-v1` branch (~251 commits ahead of `main`), the base has shifted:

| # | Previous draft assumption | New anchor (`citadel-v1`) | Why it matters |
|---|---|---|---|
| 1 | Fork `main` of `ai-hub-gateway-solution-accelerator` | Fork **`citadel-v1` branch** — the official Layer 1 reference implementation, rebranded "Citadel Governance Hub" | We inherit the Citadel naming, AGT integration hooks, and the WAF alignment work without re-doing it |
| 2 | Folder root `infra/` | Folder root **`bicep/infra/`** | All file paths in this plan have been retargeted accordingly |
| 3 | Ingestion via `src/usage-ingestion-function/` (C# Function) | Ingestion via **`src/usage-ingestion-logicapp/`** (Logic App workflow) | Phase 2 and Phase 4's outbound counter update target Logic App actions, not Function code |
| 4 | OpenAI-only API surface → invent new `/anthropic` API | **Unified AI Wildcard API** already exists in `citadel-v1` and abstracts across providers | Phase 0 starts with an investigation: extend the Unified AI API first, only fork to a dedicated Anthropic API if it cannot model `POST /v1/messages` + SSE faithfully |
| 5 | JWT auth treated as net-new policy work | **`citadel-v1` ships JWT auth + a "Citadel JWT Authentication Tests" validation notebook + an Entra ID Authentication guide + a JWT Client Identity & Permissions guide** | Phase 1 becomes parameterization of an existing pattern, not greenfield. The notebook is reused for verification. |
| 6 | Custom Cosmos `budgets` container designed in isolation | Express budgets as a **superset overlay on top of Citadel Access Contracts** (which already declare `Usage quotas and cost limits` per contract) | Keeps governance IaC-as-code, audit-traceable, and consistent with how the rest of Citadel onboards use-cases. Per-user × per-model overlays are still required because contracts are per-agent/per-use-case, not per-human-user. |
| 7 | Citadel framing implicit | Explicit Citadel layer map: **all 4 phases sit in Layer 1**; Layer 2 (Foundry Control Plane), Layer 3 (Agent 365), and Layer 4 (Defender/Purview/Entra) are **out-of-scope follow-ons** but referenced for forward-compatibility | Sets expectations with security/compliance stakeholders that the POC delivers governance-hub scope, not the full Citadel stack |
| 8 | `azd` bootstrap implicit | `azd init --template Azure-Samples/ai-hub-gateway-solution-accelerator -e citadel-budgets-dev --branch citadel-v1` | Lock-in of the source branch at template-init time |

No functional decisions (D1–D6) change. Phase numbering is preserved for traceability.

## Live findings (bootstrap, 2026-05-13)

Upstream `citadel-v1` cloned read-only to `_upstream/` for reference. Direct file inspection confirms / refines plan assumptions:

| # | Finding | Plan impact |
|---|---------|-------------|
| L1 | `bicep/infra/`, `src/usage-ingestion-logicapp/`, `validation/`, `bicep/infra/citadel-access-contracts/` all exist as cited. | No change. |
| L2 | `bicep/infra/citadel-access-contracts/` ships only `policies/` + `modules/` subdirs — **no `citadel-tiers/` or `user-overrides/` yet**. Those are net-new under our fork (Phase 4d). | Confirms greenfield work; matches plan. |
| L3 | Policy fragments include **both** `frag-aad-auth.xml` **and** `frag-entra-auth.xml`. Plan currently cites `frag-aad-auth.xml`. | Phase 0.a/Phase 1 must determine which is the canonical / current entry-point and pin that in the plan. |
| L4 | `frag-llm-usage.xml` exists alongside `frag-ai-usage.xml`, `frag-openai-usage.xml`, `frag-openai-usage-streaming.xml`, `frag-set-llm-usage.xml`. Suggests the **Unified AI Wildcard API has a provider-agnostic usage emitter pattern**. | Increases Path A (extend Unified AI) feasibility — Phase 0.a should evaluate whether `frag-llm-usage.xml` (or `frag-set-llm-usage.xml`) can be extended for Anthropic instead of forking `frag-ai-usage.xml`. |
| L5 | Existing validation notebooks include `citadel-unified-ai-api-tests.ipynb`, `citadel-access-contracts-tests.ipynb`, `citadel-jwt-authentication-tests.ipynb`. | Phase 0.a uses `citadel-unified-ai-api-tests.ipynb` against an Anthropic deployment; Phase 1 extends `citadel-jwt-authentication-tests.ipynb`; Phase 4 extends `citadel-access-contracts-tests.ipynb`. |
| L6 | `_upstream/` is a `--depth 1 --single-branch citadel-v1` clone — **not** a git remote of the working tree. Working tree is not yet a git repo. | Bootstrap into the working tree (via `azd init` or `git init` + upstream remote) is **deferred** until after the Phase 0.a decision, to avoid overwriting the `.github/` planning scaffold. |
| L7 | **All three upstream auth fragments (`frag-aad-auth.xml`, `frag-aad-auth-custom.xml`, `frag-entra-auth.xml`) hard-code the v1 issuer `https://sts.windows.net/{tenant-id}/`.** This directly conflicts with `.github/copilot-instructions.md` ("v2.0 issuer, never `sts.windows.net`"). | Our Citadel fork **must** override to v2.0 issuer `https://login.microsoftonline.com/{tenant-id}/v2.0`. Captured in Phase 1 fragment draft below. Worth surfacing as a PR back to upstream `citadel-v1`. |
| L8 | `frag-aad-auth-custom.xml` ≡ `frag-entra-auth.xml` byte-identically. Fragment-id `aad-auth-custom` is the one actually included by `product-llm-oauth-access.xml`; `frag-entra-auth.xml` is dead. | Citadel forks from `frag-aad-auth-custom.xml`. `frag-entra-auth.xml` is ignored. |
| L9 | Fragment-id `aad-auth` (legacy, Named-Value-driven, single audience) is included by `openai_api_policy.xml` + `openai_api_policy_dynamic_throttling.xml`. Fragment-id `aad-auth-custom` (parameterizable via context variables) is included by `product-llm-oauth-access.xml`. | Citadel needs **per-API audience** (Claude Code app ≠ other apps), so `aad-auth-custom` is the right base. Confirmed by call-site pattern in `product-llm-oauth-access.xml`. |

## Operating mode (2026-05-13)

**No live Azure tenant / no live Foundry deployment is available.** All work is **theoretical / paper-only** until a real environment is provisioned. Concretely:

- "Open" assumptions A1, A2, A3, A5 are **deferred, not blocking** — design proceeds using named placeholders (`<claude-code-app-id>`, `<customer-tenant-id>`, `<tier-group-oid-{tier}>`, etc.) wired through Bicep parameters and `.bicepparam` files.
- "Smoke-test" / "spike" / "validation notebook" deliverables are authored as **executable artifacts that cannot yet be run** — they ship with TODO markers and a `## Validation gate` section listing the exact preconditions (tenant, app reg, deployment) needed to run them.
- Phase 0.a (Path A vs Path B) is decided **on paper** from the upstream code + guides + Anthropic API skill. The decision row records "decided theoretically, pending live confirmation."
- No `azd up`, no `az deployment`, no real HTTP calls. `bicep build` / lint / what-if dry-runs against a synthetic subscription ID are acceptable.
- Anything that genuinely requires a live tenant (e.g., reading actual JWT claim shape) is captured as a **Validation gate** row in the relevant phase, not as a blocker on the design.

## Open assumptions (deferred — paper design proceeds with placeholders)

| # | Assumption | Placeholder used in artifacts | Needed live by | Status |
|---|-----------|------------------------------|----------------|--------|
| A1 | **Claude Code Entra app ID** (the `aud` value the multi-tenant Anthropic-published app uses against customer tenant). | Bicep param `claudeCodeAppId` / Named Value `claude-code-app-id` / placeholder string `<claude-code-app-id>` | First real Phase 1 deployment | 🅿️ deferred (paper) |
| A2 | **Tier → Entra group mapping** (group object IDs + tier names). | `tierGroupMap` map in `bicepparam` keyed `<tier-group-oid-bronze>` / `<tier-group-oid-silver>` / `<tier-group-oid-gold>` | First real Phase 4b tier-sync run | 🅿️ deferred (paper) |
| A3 | **Foundry-hosted Anthropic model deployment** reachable from a dev subscription. | Backend URL placeholder `<foundry-anthropic-endpoint>`; deployment name placeholder `<claude-deployment-name>` | First real Phase 0.a smoke test | 🅿️ deferred (paper) |
| A4 | ~~`frag-aad-auth.xml` vs `frag-entra-auth.xml`~~ — **resolved (2026-05-13)**: use `frag-aad-auth-custom.xml` (fragment-id `aad-auth-custom`) as the base. `frag-entra-auth.xml` is a dead duplicate (L8). `frag-aad-auth.xml` is the legacy single-audience path. See Phase 1 fragment draft below. | n/a | n/a | ✅ resolved |
| A5 | **Claude Code supports custom Anthropic-compatible base URL with Entra auth** (Risk #1). | Documented as a **Validation gate** in Phase 0.a; design assumes "yes" with fallback documented if "no". | First real Phase 0 smoke test | 🅿️ deferred (paper) |

## Phase 0.a spike — tracking row

| Item | Value |
|------|-------|
| Status | 🟡 to be decided on paper (no live Foundry available — see Operating mode) |
| Decision | Path A (extend Unified AI Wildcard) **or** Path B (dedicated `/anthropic` API) — undecided |
| Inputs | A3, A4, A5 above; `citadel-unified-ai-api-tests.ipynb`; `_upstream/bicep/infra/modules/apim/policies/frag-llm-usage.xml`; `_upstream/guides/` |
| Decision criteria | (1) Can Unified AI carry Anthropic's `POST /v1/messages` + SSE without lossy normalization? (2) Does `frag-llm-usage.xml` already capture `usage.input_tokens`/`usage.output_tokens` semantically? (3) Streaming usage capture parity with `frag-openai-usage-streaming.xml`? (4) Backend auth via APIM MI works against Foundry's Anthropic endpoint? (5) Effort to maintain a second API surface (Path B) vs. provider-branch policy logic (Path A)? (6) Impact on PBIX schema. |
| Output | One row appended below this table with decision, rationale, and date. Plan body sections Phase 0.b through Phase 4 then collapse to the chosen path. |

### Phase 0.a paper decision (2026-05-13)

| Field | Value |
|-------|-------|
| Decision | **Path B — dedicated `/anthropic` API** |
| Mode | Paper-only (no live Foundry; pending live confirmation on first deploy) |
| Rationale | (1) Anthropic Messages API is structurally distinct from OpenAI Chat Completions — different request shape (`messages` with `content` blocks vs flat `messages` strings), different SSE event taxonomy (`message_start`/`content_block_delta`/`message_delta` vs `data: {...}` chunks), different usage location (`usage.input_tokens`+`usage.output_tokens` vs `usage.total_tokens`). Forcing Unified AI normalization risks lossy passthrough. (2) Cleaner customer-facing story: "here is the Anthropic surface, with its own policy stack". (3) No coupling risk — extending Unified AI's existing OpenAI-shaped policies could regress production OpenAI consumers. (4) Maintenance cost of a second API is bounded: ~5 policy fragments + 1 OpenAPI spec, all forked from existing OpenAI equivalents. (5) Validation reuses `citadel-jwt-authentication-tests.ipynb` + new `citadel-anthropic-surface-tests.ipynb`, no churn in `citadel-unified-ai-api-tests.ipynb`. |
| Live confirmation needed (Validation gate) | (a) Foundry's Anthropic endpoint accepts APIM-MI bearer tokens with Foundry resource scope; (b) Claude Code accepts a custom base URL while sending Entra-issued bearer; (c) SSE `message_delta` terminal event carries final `usage.output_tokens` as documented. |
| Plan impact | Phase 0.b authored against Path B file list. Path A references collapsed but not deleted (kept as a "future consolidation" note in `CITADEL-OVERLAY.md`). |

## Phase 1 — proposed fragment draft (pending A1)

**Decision (from L7 + L8 + L9 + A4):** fork `frag-aad-auth-custom.xml` as `frag-citadel-anthropic-auth.xml`. Call from the Anthropic API (Path A: inside Unified AI API; Path B: inside dedicated `/anthropic` API) following the pattern in `product-llm-oauth-access.xml` — i.e., caller pre-sets context variables, includes the fragment.

The fragment differs from upstream in three ways:
1. **v2.0 issuer** (fixes L7, complies with `.github/copilot-instructions.md`).
2. **No `appid` required-claim** — Claude Code's JWT is issued by the Anthropic-published multi-tenant app; we cannot constrain `appid` because we don't own the app manifest. Audience pinning + tenant pinning is sufficient.
3. **Capture `oid` and `preferred_username` into context variables** for downstream usage-emission (Phase 2) and budget enforcement (Phase 4c) fragments.

Illustrative (NOT copy-paste production — needs review against canonical `frag-aad-auth-custom.xml`):

```xml
<fragment>
    <!-- Citadel Anthropic auth: per-API parameterizable; v2.0 issuer; captures oid + preferred_username -->
    <set-variable name="citadel-tenant-id" value="@(context.Variables.GetValueOrDefault("citadel-tenant-id", "{{tenant-id}}"))" />
    <set-variable name="citadel-audience" value="@(context.Variables.GetValueOrDefault("citadel-audience", "{{claude-code-app-id}}"))" />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401"
            failed-validation-error-message="Unauthorized" require-expiration-time="true"
            require-scheme="Bearer" require-signed-tokens="true"
            output-token-variable-name="citadel-jwt">
        <openid-config url="@($"https://login.microsoftonline.com/{context.Variables["citadel-tenant-id"]}/v2.0/.well-known/openid-configuration")" />
        <audiences>
            <audience>@((string)context.Variables["citadel-audience"])</audience>
        </audiences>
        <issuers>
            <issuer>@($"https://login.microsoftonline.com/{context.Variables["citadel-tenant-id"]}/v2.0")</issuer>
        </issuers>
    </validate-jwt>
    <!-- Extract identity claims for downstream usage + budget fragments -->
    <set-variable name="userOid" value="@(((Jwt)context.Variables["citadel-jwt"]).Claims.GetValueOrDefault("oid", "NA"))" />
    <set-variable name="userUpn" value="@(((Jwt)context.Variables["citadel-jwt"]).Claims.GetValueOrDefault("preferred_username", "NA"))" />
</fragment>
```

Named Values to provision (Phase 1 Bicep, in `apim.bicep`):
- `tenant-id` — already exists upstream; reuse.
- `claude-code-app-id` — **new** Named Value, value sourced from A1 (open).

Call-site pattern (illustrative, in `anthropic-api-policy.xml` or the Unified AI API policy inbound):

```xml
<inbound>
    <base />
    <set-variable name="citadel-audience" value="{{claude-code-app-id}}" />
    <include-fragment fragment-id="citadel-anthropic-auth" />
    <!-- strip user Authorization before forwarding; APIM MI handles backend auth -->
    <set-header name="Authorization" exists-action="delete" />
</inbound>
```

**Still blocked on A1** (Claude Code Entra app ID) to set the `claude-code-app-id` Named Value. Once A1 is supplied, the fragment file can be created at `bicep/infra/modules/apim/policies/frag-citadel-anthropic-auth.xml` and registered in `apim.bicep` alongside the existing fragment block (line ~726 of upstream `apim.bicep`).

## Locked decisions
- **Identity (D1):** Pass-through Entra JWT. Audience = Anthropic-published Claude Code app ID. APIM validates against customer tenant's OpenID config; extracts `oid` and `preferred_username`.
- **Granularity (D2):** Hybrid. Tier-based monthly budgets (via Entra group → Cosmos sync) **plus** per-user × per-model override records. Lookup precedence at enforcement time: `(oid, model)` → `(oid, *)` → `(tier, model)` → `(tier, *)` → global default.
- **Counter store (D3):** Cosmos (durable budgets + monthly totals) with APIM `cache-lookup-value` in front for hot reads (~30s TTL).
- **Enforcement (D4):** 80% soft warning header (`x-citadel-budget-pct`, `x-citadel-budget-remaining`), 100% hard block (HTTP 429 with `Retry-After` set to start of next calendar month). Calendar month window. Admin-override flag on budget doc bypasses block.
- **Provisioning (D5):** Phase 4 ships with Bicep-as-code only for tiers + IaC seed for global default. Power App deferred post-POC.
- **Reporting (D6):** Extend existing PBIX (`AI-Hub-Gateway-Usage-Report-v1-5-Incremental.pbix`). Fabric deferred.
- **Scope:** Steps 1–4 in scope (full enforcement, not just demo). Step 5 (Entra→tier sync) folded into Phase 4 because it's required for tier lookup to work. Step 6 (Power App) deferred.

## Constraint that reshapes everything
Claude Code authenticates to the **Anthropic-published multi-tenant Entra app**. customer's tenant admin consents to it but cannot modify its token manifest. Consequences:
- JWT will contain `oid`, `tid`, `preferred_username`/`upn`, `aud` (= Anthropic app), `iss` (customer tenant). It will **NOT** contain `groups`, `roles`, or any custom claims.
- Tier resolution must be a server-side lookup: nightly Function syncs Entra group memberships into a `user-tier` Cosmos container keyed by `/oid`. APIM does point-read.
- Validate `aud` against the known Claude Code app ID, and `tid` against customer tenant ID. Reject any other tenant.

---

## Phase 0 — Anthropic-compatible surface on the Citadel Governance Hub (PREREQUISITE)

**Adjustment vs. previous draft:** `citadel-v1` introduces a **Unified AI Wildcard API** designed to front multiple LLM providers (Azure OpenAI, Foundry, Gemini) behind a single APIM façade with provider-aware policy fragments. This collapses Phase 0 from "build a new API" to "extend an existing pattern" — *if* it can faithfully carry Anthropic's `POST /v1/messages` + SSE shape.

**Phase 0.a — Spike (1–2 days, must run first):**
1. Read [`guides/llm-routing-architecture`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides) and the Unified AI API operation/policy code under `bicep/infra` to determine whether it can model an Anthropic-shaped request/response pair (it normalizes today around an OpenAI-ish contract; Anthropic's schema is sibling, not subset).
2. Run the **"Citadel Unified AI API Tests"** validation notebook against a Foundry-hosted Anthropic deployment to see what comes back.
3. **Decision gate:**
   - **Path A (preferred):** Extend Unified AI API with a provider-specific request/response transform path (`provider=anthropic`) and a new policy fragment `frag-anthropic-usage.xml`. No new API resource.
   - **Path B (fallback):** Add a dedicated `anthropic-api` at path `/anthropic` mirroring upstream Anthropic Messages API.

**Phase 0.b — Implementation (Path B detailed; Path A is a subset):**
1. Add APIM API at path `/anthropic` (or a `provider=anthropic` route on the Unified AI API), `POST /v1/messages` + streaming via SSE. Hand-written OpenAPI spec; do not try to derive from the OpenAI spec.
2. Add backend pointing at Foundry's Anthropic-native endpoint. Use APIM managed identity → Foundry (`Authorization: Bearer {token}` from MI, scope = Foundry's resource ID).
3. Strip the inbound `Authorization` header (user JWT) before forwarding — Foundry must NOT see it. User identity is retained only as APIM context variables for budget/telemetry.
4. Create policy fragment `frag-anthropic-usage.xml` (forked from existing `frag-ai-usage.xml`) that reads `usage.input_tokens` + `usage.output_tokens` and maps them to the existing `promptTokens`/`responseTokens`/`totalTokens` Event Hub fields, so the Logic App ingestion and PBIX stay schema-compatible.
5. Handle SSE streaming: tokens come in the terminal `message_delta` event with `usage.output_tokens`. Mirror the approach used by `frag-openai-usage-streaming.xml`.

Files (in fork, paths reflect `citadel-v1` layout):
- `bicep/infra/modules/apim/anthropic/anthropic-api-spec.yaml` (new — Path B only)
- `bicep/infra/modules/apim/policies/anthropic-api-policy.xml` (new — Path B only)
- `bicep/infra/modules/apim/policies/frag-anthropic-usage.xml` (new, fork of `frag-ai-usage.xml`)
- `bicep/infra/modules/apim/policies/frag-anthropic-usage-streaming.xml` (new, fork of `frag-openai-usage-streaming.xml`)
- `bicep/infra/modules/apim/apim.bicep` — register new API/fragment mirroring the existing API-registration block

## Phase 1 — Identity injection (depends on Phase 0)

**Adjustment vs. previous draft:** `citadel-v1` already ships a working JWT auth pattern plus three reference assets we reuse instead of reinventing: the *Entra ID Authentication* guide, the *JWT Client Identity & Permissions* guide, and the *Citadel JWT Authentication Tests* validation notebook. Phase 1 becomes parameter-set + claim-extraction work on top.

1. Configure `frag-aad-auth.xml`'s `validate-jwt`: set `audience` Named Value to Claude Code app client ID; set `issuer` to `https://login.microsoftonline.com/{customer-tenant-id}/v2.0` (v2.0 issuer, not `sts.windows.net`).
2. After validation, add `<set-variable name="userOid" value="@(((Jwt)context.Variables["validatedJwt"]).Claims["oid"].FirstOrDefault())" />` and same for `upn`/`preferred_username`. Wire `userOid` into the existing `endUserId` variable so the Event Hub schema is unchanged.
3. Add `<return-response>` 401 on missing `oid` claim (defense-in-depth — should never happen with a valid Entra token).
4. Update Named Values: `tenant-id`, `audience`, plus new `claude-code-app-id` (= audience).
5. Include `aad-auth` fragment in the Anthropic-surface inbound section (whether Path A or Path B from Phase 0).
6. **Adapt** the existing *Citadel JWT Authentication Tests* notebook with a new test case targeting the Anthropic surface and asserting `oid` is captured.

Files:
- `bicep/infra/modules/apim/policies/frag-aad-auth.xml` — update
- `bicep/infra/modules/apim/apim.bicep` — update Named Values
- `bicep/infra/main.bicep` — add `claudeCodeAppId` param
- `validation/citadel-jwt-authentication-tests.ipynb` — add Anthropic test case

## Phase 2 — Telemetry enrichment (depends on Phase 1, parallel with Phase 3 prep)

**Adjustment vs. previous draft:** ingestion is no longer a C# Azure Function. `citadel-v1` ships a **Logic App workflow** under `src/usage-ingestion-logicapp/` that consumes the Event Hub stream and writes to Cosmos. We update the workflow definition, not Function/Stream-Analytics code. Verify at spike time whether Stream Analytics still exists in `citadel-v1` — if so, treat it as legacy and route through the Logic App.

1. Add `userOid` and `userUpn` as top-level fields in the Event Hub JSON payload built by `frag-anthropic-usage.xml`. `endUserId` already exists — populate it from `userOid` for backward compatibility with PBIX.
2. Update the **usage-ingestion Logic App workflow** definition to project `userOid`, `userUpn` from the Event Hub message into the Cosmos `ai-usage-container` doc.
3. Compute and project a `month` field (`yyyy-MM`, UTC) in the same Logic App action — the partition slice for budget aggregation queries.
4. **Repartition decision (unchanged):** do NOT change `ai-usage-container` partition key (`/productName`) — migration is costly. Per-user queries will fan out; acceptable at POC scale. Documented as a known scale limit.
5. Add a new container `ai-usage-monthly` partitioned by `/oid` for the running monthly totals (Phase 4 writes here too).
6. Extend the Logic App with a second branch that upserts into `ai-usage-monthly` (atomic Cosmos `Patch` with `Add` on `totalTokens`, keyed by `<oid>:<month>:<model>`).

Files:
- `bicep/infra/modules/apim/policies/frag-anthropic-usage.xml` — extend log-to-eventhub body
- `bicep/infra/modules/apim/policies/frag-anthropic-usage-streaming.xml` — same
- `src/usage-ingestion-logicapp/` — extend workflow definition (Logic App standard / consumption — match upstream)
- `bicep/infra/modules/cosmos-db/cosmos-db.bicep` — add `ai-usage-monthly` container (`/oid` PK)

## Phase 3 — Per-user PBI reporting (parallel with Phase 4 dev once Phase 2 ships)

1. Open `src/usage-reports/AI-Hub-Gateway-Usage-Report-v1-5-Incremental.pbix` in PBI Desktop.
2. In Power Query, refresh schema on `ai-usage-container` query so `userOid` and `userUpn` appear.
3. Add `userUpn` (display) and `userOid` (key) as a new dimension. `userUpn` is the human-readable; `userOid` is the stable join key.
4. New page "Usage by User" with: bar chart tokens by `userUpn`, slicer by `model`, table with `userUpn × model × tokens × cost` (cost calc via existing `model-pricing` join).
5. Add page "Top consumers (last 30d)" using a relative date filter.
6. Republish PBIX to fork at same path. Document refresh schedule.

Files:
- `src/usage-reports/AI-Hub-Gateway-Usage-Report-v1-5-Incremental.pbix` — update in place (binary)
- `guides/power-bi-dashboard.md` — append section "Per-user reporting"

## Phase 4 — Budget store + enforcement + Entra tier sync (depends on Phase 2)

**Adjustment vs. previous draft:** budgets are no longer a free-standing custom container. They become a **superset extension of Citadel Access Contracts** (`bicep/infra/citadel-access-contracts/`). Access Contracts already model `Usage quotas and cost limits` per use-case in Bicep — we add **tier overlays** and **per-user-per-model overlays** to that schema. The Cosmos containers below back the runtime view of those contracts (APIM reads from Cosmos, IaC writes to Cosmos via Access Contract deployment). This keeps audit-traceability through IaC commits and aligns with how Citadel onboards every other use-case.

### 4a. Cosmos schema (runtime view of Access Contracts)
New containers in existing `usage` database:
- `budgets`, PK `/scope`. Scope values: `tier:<tierName>`, `user:<oid>`, `global`. Seeded by Access Contract deployments. Doc shape:
  ```json
  {
    "id": "tier:power-users",
    "scope": "tier:power-users",
    "monthlyTokenLimit": 5000000,
    "perModelOverrides": { "claude-opus-4": 2000000 },
    "softWarnPct": 80,
    "hardBlockPct": 100,
    "adminOverride": false,
    "sourceContract": "contracts/citadel-tiers/power-users.bicep",
    "updatedAt": "2026-05-01T00:00:00Z",
    "updatedBy": "iac"
  }
  ```
- `user-tier`, PK `/oid`. Doc shape: `{ "id": "<oid>", "oid": "<oid>", "tier": "power-users", "upn": "...", "lastSyncedAt": "..." }`. Default tier if no doc: `standard`.
- `ai-usage-monthly` (from Phase 2), PK `/oid`. Doc id = `<oid>:<month>:<model>`. Updated by the **Logic App ingestion workflow** on each Event Hub message (atomic Cosmos `Patch` op `Add` on `totalTokens`).

### 4b. Tier sync Function
- New timer-triggered Function `src/tier-sync-function/` runs every 6h.
- Uses Managed Identity → Microsoft Graph `/groups/{id}/transitiveMembers` for each configured tier group.
- Writes/updates `user-tier` container. Removes orphans (users no longer in any tier group → revert to default).
- Group→tier mapping declared in the **Citadel Access Contract** for that tier (see 4d below), surfaced to the Function via Bicep-generated app settings.

### 4c. APIM enforcement policy
New fragment `frag-citadel-budget-check.xml` included in `anthropic-api-policy.xml` inbound, AFTER `aad-auth`:
1. `cache-lookup-value` for key `tier:{oid}` (30s TTL); on miss, `send-request` to Cosmos `user-tier` point-read, `cache-store-value`.
2. Same pattern for budget doc: try `user:{oid}:{model}`, fall back to `user:{oid}`, `tier:{tier}:{model}`, `tier:{tier}`, `global`.
3. `send-request` to Cosmos query `ai-usage-monthly` for `(oid, month, model)` — also cached 30s.
4. Compute `pct = currentTokens / limit`. Set response headers `x-citadel-budget-pct`, `x-citadel-budget-remaining`.
5. If `pct >= 1.0` AND `!adminOverride`: `<return-response>` 429 with `Retry-After` = seconds until next month UTC, body explaining the block and contact.
6. Outbound: after Anthropic response parsed (token counts available), `send-request` PATCH to `ai-usage-monthly` to increment counter — fire-and-forget, don't block response.

### 4d. IaC seed via Citadel Access Contracts (illustrative example)
**Adjustment vs. previous draft:** instead of a free-standing `citadel-tiers.bicep` module, we extend the Access Contract schema with a `userBudgets` block. Each tier is its own contract; per-user overrides are individually-named contracts under `user-overrides/`. This makes every budget change a reviewable Bicep PR — the audit trail.

Illustrative `bicep/infra/citadel-access-contracts/citadel-tiers/power-users.bicep`:
```bicep
param budgetScope string = 'tier:power-users'
param entraGroupObjectId string  // synced into user-tier by 4b
param monthlyTokenLimit int = 5000000
param perModelOverrides object = { 'claude-opus-4': 2000000 }

// emits a deployment-script that upserts the budgets doc
module budgetSeed '../_shared/budget-seed.bicep' = { ... }
```
Upstream `Tier:tier:power-users` and `User:user:<oid>` contracts deploy through the same Access Contract pipeline that already onboards LLMs and use-cases.

Files:
- `bicep/infra/modules/cosmos-db/cosmos-db.bicep` — add `budgets`, `user-tier` containers
- `bicep/infra/modules/apim/policies/frag-citadel-budget-check.xml` (new)
- `bicep/infra/modules/apim/policies/anthropic-api-policy.xml` (or Unified AI API policy if Path A) — include fragment
- `bicep/infra/modules/apim/apim.bicep` — register new fragment
- `src/tier-sync-function/` (new: function code + bicep module)
- `bicep/infra/citadel-access-contracts/citadel-tiers/*.bicep` + `.bicepparam` (one per tier)
- `bicep/infra/citadel-access-contracts/_shared/budget-seed.bicep` (new — shared upsert helper)

---

## Relevant upstream files (Citadel Governance Hub — branch `citadel-v1`)

**Adjustment vs. previous draft:** all references retargeted from `main` to `citadel-v1`, and from `infra/` to `bicep/infra/`. Newly-added Citadel-specific references included.

- [`bicep/infra/` (root)](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1/bicep/infra) — IaC entrypoint
- [`bicep/infra/citadel-access-contracts/`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1/bicep/infra/citadel-access-contracts) — Access Contracts pattern we extend for tiers/users
- [`bicep/infra/modules/apim/policies/frag-aad-auth.xml`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/bicep/infra/modules/apim/policies/frag-aad-auth.xml) — JWT pattern to parameterize
- [`bicep/infra/modules/apim/policies/frag-ai-usage.xml`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/bicep/infra/modules/apim/policies/frag-ai-usage.xml) — template for Anthropic variant
- [`bicep/infra/modules/apim/policies/frag-openai-usage-streaming.xml`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/bicep/infra/modules/apim/policies/frag-openai-usage-streaming.xml) — streaming pattern
- [`bicep/infra/modules/apim/apim.bicep`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/bicep/infra/modules/apim/apim.bicep) — API registration + Named Values patterns
- [`bicep/infra/modules/cosmos-db/cosmos-db.bicep`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/bicep/infra/modules/cosmos-db/cosmos-db.bicep) — container resource pattern
- [`src/usage-ingestion-logicapp/`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1/src/usage-ingestion-logicapp) — **Logic App** ingestion workflow (replaces Function-based ingestion from `main`)
- [`validation/`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1/validation) — JWT auth tests, Access Contracts tests, Unified AI API tests — reused for verification
- [`guides/entra-id-authentication.md`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides) and `guides/jwt-client-identity-and-permissions.md` — operational references for Phase 1
- [`guides/power-bi-dashboard.md`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/power-bi-dashboard.md) — PBIX extension guide
- [`CITADEL-TECHNICAL-GUIDE.md`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/CITADEL-TECHNICAL-GUIDE.md) and [`Citadel-WAF-Alignment.md`](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/Citadel-WAF-Alignment.md) — architectural context

## Verification
**Phase 0:**
- `curl` Anthropic Messages API through APIM with a valid Entra token, assert 200 and proper Anthropic response shape (including streaming SSE).
- Configure a local Claude Code instance to point at the APIM endpoint, verify a real conversation works end-to-end.

**Phase 1:**
- Invalid JWT → 401. Wrong audience → 401. Wrong tenant → 401. Valid token → 200 and `userOid` variable populated (assert via trace policy).

**Phase 2:**
- Make a call; verify Event Hub message in App Insights contains non-`NA` `userOid` and `userUpn`. Query Cosmos `ai-usage-container` for new doc with those fields. Verify SA query promoted them.

**Phase 3:**
- Refresh PBIX, confirm new dimension surfaces. Generate test traffic from two distinct Entra users; verify they appear separately in "Usage by User" page.

**Phase 4:**
- Seed a `user:<oid>` budget doc with limit=1000 tokens; make calls until block. Assert: `x-citadel-budget-pct` header increments, 80% warning observed, 100% returns 429 with correct `Retry-After`.
- Set `adminOverride=true`, assert calls proceed despite over-limit.
- Run tier-sync Function manually; verify `user-tier` docs match Entra group membership.
- Verify cache invalidation: after Function update, APIM picks up new tier within 30s TTL.
- Load test: 50 concurrent requests should not cause double-counting (Cosmos PATCH is idempotent per request via `requestId` in counter doc).

## Risks / Further Considerations
1. **Claude Code endpoint override:** confirm Claude Code supports pointing at a custom Anthropic-compatible base URL while keeping Entra auth. If not, Phase 0's facade is moot. **Recommendation:** validate this in week 1 with a smoke test before committing the rest.
2. **Foundry's Anthropic API surface fidelity:** if Foundry's Anthropic endpoint deviates from upstream Anthropic (e.g., different model IDs, missing features), the APIM facade must reconcile. **Recommendation:** scope Phase 0 to exactly the surface Claude Code uses (`POST /v1/messages` + streaming); defer other endpoints.
3. **Concurrent-request race on counter:** between budget read and outbound increment, a user can burst over their limit. **Recommendation:** accept the small overage at POC; for prod, add an inbound provisional reservation (estimate from prompt tokens) and reconcile on outbound.
4. **JWT in cache key:** never cache `pct`/`remaining` per-user across users — ensure `varyByDeveloper` semantics in `cache-lookup-value` (use `oid` in the key).
5. **`preferred_username` vs `upn`:** for guest users `upn` is null. Use `preferred_username` as display, `oid` as identity. Document this in PBIX.
6. **Audience constraint reversal:** if the customer can negotiate Claude Code → custom the customer app registration, the tier-sync Function becomes optional (groups travel in the JWT). Worth a separate conversation with the Anthropic field team.
7. **Access Contracts overlap:** Citadel Access Contracts already declare `Usage quotas and cost limits` per contract. Our per-user × per-model budgets are a **superset overlay** — *not* a replacement. We must avoid double-counting (two enforcement points hitting the same request) and clearly document precedence: contract-level quota is the use-case ceiling; our per-user budget enforces fair-share *within* that ceiling. **Recommendation:** call out this layering in the Citadel Technical Guide fork.
8. **Unified AI API vs. dedicated Anthropic API (Phase 0 decision gate):** Path A keeps us inside the upstream pattern but risks impedance mismatch with Anthropic's response schema; Path B is faster but adds a parallel API surface to maintain. **Recommendation:** time-box the Phase 0.a spike to 2 days and commit to one path before starting Phase 1.

## Out of scope (POC)
- Power App admin UI for overrides (Step 6 from original list)
- Microsoft Fabric migration
- Cost-based budgets (only token-based in POC; conversion lives in PBIX)
- Multi-region / DR for Cosmos budgets container
- Audit log of budget changes (IaC commits are the audit trail at POC)
