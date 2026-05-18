/**
 * Citadel tier-sync Function.
 *
 * Purpose: maintain the `user-tier` Cosmos container that the APIM `citadel-budget-check` fragment
 *          uses to resolve a request to a tier (D2 precedence step 3-4).
 *
 * Why this exists: the Claude Code JWT is issued by an Anthropic-published multi-tenant Entra app
 *                  whose manifest the customer does NOT control. There are no `groups` or `roles`
 *                  claims. Tier resolution MUST happen server-side from a directory snapshot.
 *
 * Schedule: every 6 hours (NCRONTAB "0 0 *​/​6 * * *"). Drift between runs is bounded by tier
 *           budget headroom — picking up a new gold member 6h late only affects the next 6h.
 *
 * Algorithm:
 *   1. For each tier in TIER_GROUP_MAP (sorted by tier priority HIGH -> LOW: gold > silver > bronze):
 *        - Call Microsoft Graph /groups/{oid}/transitiveMembers/microsoft.graph.user
 *          (pagination via @odata.nextLink).
 *   2. Build an in-memory map: oid -> highest-tier-seen.
 *   3. Diff against current Cosmos `user-tier` documents and:
 *        - Upsert new/changed (oid, tier) pairs.
 *        - Mark removed users for orphan handling (default behaviour: leave them but flag "bronze"
 *          so they fall back to the safest tier).
 *   4. Log a summary to Application Insights.
 *
 * Required identity permissions (granted via Bicep):
 *   - Microsoft Graph: Group.Read.All, Directory.Read.All  (Application permission, admin-consented)
 *   - Cosmos data plane: 'Cosmos DB Built-in Data Contributor' role assignment on the account
 */

import { AzureFunction, Context } from "@azure/functions";
import { CosmosClient } from "@azure/cosmos";
import { ClientSecretCredential, DefaultAzureCredential } from "@azure/identity";
import { Client as GraphClient } from "@microsoft/microsoft-graph-client";
import "isomorphic-fetch";

// Tier priority — HIGHEST first. If a user is in multiple tier groups, the first match wins.
const TIER_PRIORITY: Array<{ tier: string; groupOidEnv: string }> = [
  { tier: "gold",   groupOidEnv: "TIER_GROUP_OID_GOLD"   },
  { tier: "silver", groupOidEnv: "TIER_GROUP_OID_SILVER" },
  { tier: "bronze", groupOidEnv: "TIER_GROUP_OID_BRONZE" },
];

const DEFAULT_FALLBACK_TIER = "bronze";

const COSMOS_ACCOUNT = process.env.COSMOS_ACCOUNT_NAME!;
const COSMOS_DB      = "ai-usage-db";
const COSMOS_CTNR    = "user-tier";

const timerTrigger: AzureFunction = async function (context: Context, timer: any): Promise<void> {
  const startedAt = Date.now();
  context.log("[tier-sync] starting", { startedAt: new Date(startedAt).toISOString() });

  // 1) Auth — Function MI to Graph + Cosmos.
  const cred = new DefaultAzureCredential();
  const graph = GraphClient.initWithMiddleware({
    authProvider: {
      getAccessToken: async () =>
        (await cred.getToken("https://graph.microsoft.com/.default"))!.token,
    },
  });
  const cosmos = new CosmosClient({
    endpoint: `https://${COSMOS_ACCOUNT}.documents.azure.com:443/`,
    aadCredentials: cred,
  });
  const container = cosmos.database(COSMOS_DB).container(COSMOS_CTNR);

  // 2) Build oid -> tier map by walking groups in priority order.
  const oidToTier = new Map<string, string>();
  for (const { tier, groupOidEnv } of TIER_PRIORITY) {
    const groupOid = process.env[groupOidEnv];
    if (!groupOid || groupOid.startsWith("<")) {
      context.log.warn(`[tier-sync] skipping tier '${tier}': ${groupOidEnv} not set or still a placeholder`);
      continue;
    }
    let url: string | null =
      `/groups/${groupOid}/transitiveMembers/microsoft.graph.user?$select=id,userPrincipalName&$top=999`;
    while (url) {
      const page: any = await graph.api(url).get();
      for (const u of page.value as Array<{ id: string; userPrincipalName: string }>) {
        if (!oidToTier.has(u.id)) {
          oidToTier.set(u.id, tier);
        }
      }
      url = page["@odata.nextLink"]
        ? page["@odata.nextLink"].replace("https://graph.microsoft.com/v1.0", "")
        : null;
    }
    context.log(`[tier-sync] tier=${tier} cumulative-mapped=${oidToTier.size}`);
  }

  // 3) Upsert into Cosmos `user-tier`.
  let upserted = 0;
  for (const [oid, tier] of oidToTier.entries()) {
    await container.items.upsert({
      id: oid,
      oid,
      tier,
      updatedAt: new Date().toISOString(),
    });
    upserted++;
  }

  // 4) Orphan handling: existing docs not in the new map fall back to bronze.
  const { resources: existing } = await container.items
    .query<{ id: string; oid: string; tier: string }>({
      query: "SELECT c.id, c.oid, c.tier FROM c",
    })
    .fetchAll();
  let demoted = 0;
  for (const doc of existing) {
    if (!oidToTier.has(doc.oid) && doc.tier !== DEFAULT_FALLBACK_TIER) {
      await container.items.upsert({
        id: doc.oid,
        oid: doc.oid,
        tier: DEFAULT_FALLBACK_TIER,
        updatedAt: new Date().toISOString(),
        demotedAt: new Date().toISOString(),
      });
      demoted++;
    }
  }

  context.log("[tier-sync] complete", {
    upserted,
    demoted,
    elapsedMs: Date.now() - startedAt,
  });
};

export default timerTrigger;
