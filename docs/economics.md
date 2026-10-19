# AI Assistant Unit Economics & Pricing Model (2026)

## 1. Executive Summary

This document outlines the unit economics for **The Go-getters AI Assistant** across Free and Pro tiers, accounting for LLM token pricing, Lemon Squeezy merchant of record fees, infrastructure overhead, and subscription profitability.

---

## 2. Plan Entitlements & Pricing

| Parameter | Free Tier | Pro Tier ($9.99 / month) |
| :--- | :--- | :--- |
| **Price** | $0.00 | $9.99 / mo (billed via Lemon Squeezy) |
| **Daily Message Limit** | 40 requests/day | 400 requests/day |
| **Max Context Input** | 4,000 tokens | 32,000 tokens |
| **Max Output Tokens** | 1,024 tokens | 4,096 tokens |
| **Allowed Models** | `nvidia/nemotron-3-ultra-550b-a55b:free`<br>`cohere/north-mini-code:free`<br>`openai/gpt-4o-mini` | All Free models +<br>`openai/gpt-4o`<br>`anthropic/claude-3.5-sonnet`<br>`deepseek/deepseek-r1`<br>`meta-llama/llama-3.3-70b-instruct` |
| **Concurrent Active Streams** | 1 stream | 3 streams |
| **History Context Window** | Last 10 messages | Last 30 messages |

---

## 3. Cost Breakdown per Generation

### Model Costs per 1M Tokens (Current Official Pricing)
1. **Nvidia Nemotron 550B & Cohere Code (Free):** $0.00 / 1M input, $0.00 / 1M output.
2. **GPT-4o mini:** $0.15 / 1M input, $0.60 / 1M output.
   - *Avg query (600 in, 350 out):* `(600 * 0.00000015) + (350 * 0.00000060) = $0.00009 + $0.00021 = $0.0003` (0.03 cents).
3. **GPT-4o:** $2.50 / 1M input, $10.00 / 1M output.
   - *Avg query (1,200 in, 600 out):* `(1200 * 0.0000025) + (600 * 0.000010) = $0.0030 + $0.0060 = $0.0090` (0.9 cents).
4. **Claude 3.5 Sonnet:** $3.00 / 1M input, $15.00 / 1M output.
   - *Avg query (1,200 in, 600 out):* `(1200 * 0.0000030) + (600 * 0.000015) = $0.0036 + $0.0090 = $0.0126` (1.26 cents).

---

## 4. Lemon Squeezy Merchant Fees
- **Transaction Fee:** 5% + $0.50 per successful subscription charge.
- On a **$9.99** plan:
  - Lemon Squeezy fee = `($9.99 * 0.05) + $0.50 = $0.50 + $0.50 = $1.00`.
  - **Net payout to merchant:** **$8.99 / subscriber / month**.

---

## 5. Pro Subscriber Usage Scenarios & Contribution Margin

Assumed Pro model mix: 50% GPT-4o mini / Llama 70B, 30% GPT-4o, 20% Claude 3.5 Sonnet.  
Blended cost per Pro query ≈ **$0.0048** (0.48 cents).

| Usage Level | Monthly Queries / User | Monthly AI Cost | Payment Fee | Server/DB Cost | Total Monthly Cost | Net Margin / User | Margin % |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Low** (Casual, 5 req/day) | 150 | $0.72 | $1.00 | $0.10 | $1.82 | **+$8.17** | **81.8%** |
| **Expected** (Typical, 20 req/day) | 600 | $2.88 | $1.00 | $0.20 | $4.08 | **+$5.91** | **59.2%** |
| **High** (Power user, 50 req/day) | 1,500 | $7.20 | $1.00 | $0.35 | $8.55 | **+$1.44** | **14.4%** |

*Even power users consuming 1,500 queries a month remain net positive.*

---

## 6. Free Tier Sustainability
- 80% of Free queries utilize high-quality zero-marginal-cost models (`nvidia/nemotron-3-ultra-550b-a55b:free`).
- 20% overflow to `openai/gpt-4o-mini` ($0.0003/query).
- Blended cost per Free user (averaging 5 queries/day = 150 queries/mo): **~$0.009 / user / month** (< 1 cent).
- Free-to-Pro conversion rate of **1.5%** covers the operating cost of ~1,000 Free users with just 2 Pro subscribers!
