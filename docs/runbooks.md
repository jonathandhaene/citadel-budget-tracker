# Citadel Budgets Operational Runbooks

## Table of Contents
1. [Tier-Sync Function Failure](#tier-sync-function-failure)
2. [Budget Counter Discrepancy](#budget-counter-discrepancy)
3. [Mass User Blocking Event](#mass-user-blocking-event)
4. [APIM Performance Degradation](#apim-performance-degradation)
5. [Monthly Counter Reset](#monthly-counter-reset)

---

## Tier-Sync Function Failure

### Symptoms
- Alert: "Tier-sync function execution failed"
- Users defaulting to bronze tier unexpectedly
- `user-tier` container `updatedAt` > 6 hours old

### Investigation

1. **Check Function execution logs:**
   ```bash
   az monitor log-analytics query \
     --workspace <workspace-id> \
     --analytics-query "traces | where operation_Name == 'tier-sync' | order by timestamp desc | take 50"
   ```

2. **Review Application Insights:**
   - Navigate to: Application Insights → Failures → Operations
   - Filter: `operation_Name = "tier-sync"`
   - Look for Graph API errors, Cosmos errors, or timeout exceptions

3. **Common failure modes:**
   - **Graph API throttling:** HTTP 429 responses
   - **Graph API permission denied:** HTTP 403 - check managed identity permissions
   - **Cosmos write throttling:** RU/s exceeded
   - **Timeout:** Function exceeded 5-minute limit (too many users)

### Resolution

**Graph API throttling:**
- Implement exponential backoff (already in code with pagination)
- Reduce sync frequency if user count is very large
- Consider batching users across multiple Function runs

**Permission issues:**
```bash
# Grant Graph permissions to Function MI
az ad app permission add \
  --id <function-app-id> \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 5b567255-7703-4780-807c-7be8301ae99b=Role  # Group.Read.All
```

**Cosmos throttling:**
```bash
# Increase RU/s temporarily
az cosmosdb sql container throughput update \
  --account-name <cosmos-account> \
  --database-name ai-usage-db \
  --name user-tier \
  --throughput 1000
```

**Manual sync trigger:**
```bash
# Invoke Function manually
az functionapp function invoke \
  --resource-group <rg> \
  --name <function-app-name> \
  --function-name tier-sync
```

---

## Budget Counter Discrepancy

### Symptoms
- User reports budget exhausted but usage dashboard shows < 100%
- Counter value doesn't match sum of logged requests
- Duplicate token counting suspected

### Investigation

1. **Query user's monthly counter:**
   ```bash
   # Cosmos query
   az cosmosdb sql container item read \
     --account-name <cosmos-account> \
     --database-name ai-usage-db \
     --container-name ai-usage-monthly \
     --partition-key-value "<user-oid>" \
     --id "<user-oid>:<YYYY-MM>:<model>"
   ```

2. **Sum actual usage from Event Hub:**
   ```kusto
   // Application Insights query
   customEvents
   | where name == "ai-usage"
   | where customDimensions.userOid == "<user-oid>"
   | where timestamp between (startofmonth(now()) .. now())
   | summarize TotalTokens = sum(toint(customDimensions.totalTokens))
   ```

3. **Check for duplicate events:**
   ```kusto
   customEvents
   | where name == "ai-usage"
   | where customDimensions.userOid == "<user-oid>"
   | summarize count() by tostring(customDimensions.requestId)
   | where count_ > 1
   ```

### Resolution

**Counter is too high (over-counting):**
- Root cause: duplicate Event Hub events or missing idempotency
- Fix: ensure Logic App uses `requestId` for upsert conditions
- Manual correction: update Cosmos document to correct value
- Document the correction in a git commit

**Counter is too low (under-counting):**
- Root cause: Logic App failures or Event Hub message loss
- Check Logic App run history for failures
- Verify Event Hub consumer group offset
- If confirmed: manually increment counter

**Manual counter correction template:**
```bash
# Update Cosmos document
az cosmosdb sql container item update \
  --account-name <cosmos-account> \
  --database-name ai-usage-db \
  --container-name ai-usage-monthly \
  --partition-key-value "<user-oid>" \
  --id "<user-oid>:<YYYY-MM>:<model>" \
  --body '{
    "tokensUsed": <corrected-value>,
    "correctedAt": "<timestamp>",
    "correctedBy": "<admin-oid>",
    "correctionReason": "<justification>"
  }'
```

---

## Mass User Blocking Event

### Symptoms
- Alert: "> 10% of tier users receiving HTTP 429"
- Spike in 429 responses in APIM metrics
- Multiple users reporting budget exhaustion simultaneously

### Investigation

1. **Identify affected users:**
   ```kusto
   requests
   | where resultCode == 429
   | where timestamp > ago(1h)
   | summarize BlockedUsers = dcount(tostring(customDimensions.userOid))
   ```

2. **Check for common cause:**
   - All same tier? → Tier-level budget may be too low
   - All same model? → Model-specific budget issue
   - Random distribution? → Possible system-wide counter corruption

3. **Review tier budget limits:**
   - Check `bicep/infra/citadel-access-contracts/citadel-tiers/{tier}.bicep`
   - Verify monthly limits are appropriate for expected usage

### Resolution

**Tier budget too low:**
1. Update tier contract Bicep file with higher limit
2. Create PR with justification
3. Deploy updated contract
4. Communicate timeline to users

**System-wide issue:**
1. Check APIM → Cosmos → Logic App pipeline health
2. Verify no data corruption in `budgets` container
3. If counter reset is safe: run monthly reset script early

**Communication template:**
```
Subject: Citadel Budgets - Temporary Service Impact

We're aware that multiple users are receiving budget limit errors.

Current status: [investigating | identified root cause | deployed fix]
Estimated resolution: [timeline]
Workaround: [if available]

For urgent requests, contact [AI CoE lead] for emergency override.
```

---

## APIM Performance Degradation

### Symptoms
- Alert: "APIM → Cosmos latency P95 > 500ms"
- Slow response times for Claude Code requests
- Timeout errors from budget check fragment

### Investigation

1. **Check APIM metrics:**
   - Navigate to: APIM → Metrics
   - View: "Backend Request Duration" (P95, P99)
   - Filter by: Anthropic API

2. **Identify bottleneck:**
   ```kusto
   dependencies
   | where target contains "cosmos" or target contains "documents.azure"
   | where timestamp > ago(1h)
   | summarize P95 = percentile(duration, 95), P99 = percentile(duration, 99) by target
   ```

3. **Common causes:**
   - Cosmos RU/s throttling (HTTP 429 from Cosmos)
   - APIM cache misses (check cache hit rate)
   - Cosmos cross-region latency (if multi-region)

### Resolution

**Cosmos throttling:**
```bash
# Check Cosmos metrics
az monitor metrics list \
  --resource <cosmos-resource-id> \
  --metric "TotalRequestUnits" \
  --aggregation Average

# Increase RU/s if needed
az cosmosdb sql database throughput update \
  --account-name <cosmos-account> \
  --name ai-usage-db \
  --max-throughput 4000  # autoscale
```

**Cache optimization:**
- Verify APIM cache TTL is set (~30 seconds)
- Check cache key construction includes all relevant dimensions
- Monitor cache hit rate in APIM metrics

**Network latency:**
- Ensure APIM and Cosmos are in the same region
- Consider enabling Cosmos multi-region writes if multi-region APIM

---

## Monthly Counter Reset

### Trigger
- Scheduled: 1st of every month, 00:00 UTC
- On-demand: if counter corruption is detected

### Pre-Reset Checklist

1. **Verify last month's usage is captured:**
   ```kusto
   customEvents
   | where name == "ai-usage"
   | where timestamp between (startofmonth(now(-30d)) .. endofmonth(now(-30d)))
   | summarize count()
   ```

2. **Backup current counters:**
   ```bash
   # Export current month's data
   az cosmosdb sql container item query \
     --account-name <cosmos-account> \
     --database-name ai-usage-db \
     --container-name ai-usage-monthly \
     --query "SELECT * FROM c WHERE c.id LIKE '<YYYY-MM>%'" \
     > backup-counters-$(date +%Y%m).json
   ```

3. **Notify users of reset:**
   - Post in AI CoE Teams channel
   - Confirm Power BI reports are up to date

### Reset Procedure

**Automated (via Logic App - recommended):**
- Logic App: `monthly-counter-reset-logicapp`
- Trigger: Recurrence - monthly, day 1, 00:00 UTC
- Actions:
  1. Query `ai-usage-monthly` for docs with current month key
  2. For each doc: set `tokensUsed = 0`, update `resetAt = now()`
  3. Log summary to Application Insights

**Manual (emergency):**
```bash
# Run Cosmos stored procedure (if implemented)
az cosmosdb sql container stored-procedure execute \
  --account-name <cosmos-account> \
  --database-name ai-usage-db \
  --container-name ai-usage-monthly \
  --name resetMonthlyCounters \
  --partition-key-value "all"
```

### Post-Reset Validation

1. **Verify counters reset:**
   ```bash
   # Sample query
   az cosmosdb sql container item query \
     --account-name <cosmos-account> \
     --database-name ai-usage-db \
     --container-name ai-usage-monthly \
     --query "SELECT TOP 10 * FROM c ORDER BY c._ts DESC"
   ```

2. **Test budget check:**
   - Make a Claude Code request
   - Verify `x-citadel-budget-pct` header shows low percentage
   - Check Application Insights for budget-check logs

3. **Monitor for errors:**
   - Watch for 429 errors (should be zero immediately after reset)
   - Check Logic App didn't miss any users

---

## Contact & Escalation

- **L1 Support:** AI CoE Help Desk
- **L2 Support (APIM/Cosmos):** Cloud Platform Team
- **L3 Support (Architecture):** Citadel Tech Lead
- **Emergency (production down):** Page On-Call SRE

All runbook executions should be logged in:
- Azure DevOps Work Item (for tracking)
- Git commit (for manual counter corrections)
- Teams channel (for user communication)
