# Citadel per-user budget overrides

This directory holds **per-user Citadel Access Contract overlays** — the highest-precedence layer of the D2 budget hierarchy.

## Rules

- **One file per user, one PR per change.** The git history of this folder *is* the Citadel audit log (no separate audit-log container exists in POC scope — see `CITADEL-OVERLAY.md` §5).
- **Use OID, not UPN.** OIDs are immutable; UPNs change with marriage / role change / domain migration.
- **Document the approval in the `approvalNote` parameter.** Include ticket ID, approver, and a planned expiry date.
- **`adminOverride: true` is emergency-only.** It bypasses ALL enforcement (D4). Use only with explicit C-level approval and always with a follow-up PR to revert.

## Adding an override

1. Copy `EXAMPLE-user-override.bicep` to `<oid-short>-<purpose>.bicep` (e.g. `a1b2c3d4-opus-boost.bicep`).
2. Replace `<placeholder-oid>` with the target user's Entra OID.
3. Adjust scope / monthlyTokenLimit / adminOverride / note.
4. Open a PR. Required reviewers: 1× Citadel maintainer + 1× AI governance council member.
5. On merge, the deploy pipeline runs the seed module — the override is live at next request after the APIM cache TTL (~30s).

## Removing an override

Delete the file in a PR. Same review requirements. Deploy pipeline detects deletion and runs the budget-seed module in `delete` mode (paper-only — to be wired in Phase 4b).

## Where overrides DON'T belong

- Anything that should apply to a whole tier → put it in `../citadel-tiers/{bronze,silver,gold}.bicep` instead.
- Anything that should apply to all users → put it in a future `global.bicep` (out of POC scope).
