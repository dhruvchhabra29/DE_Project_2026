# Phase 1: Problem Understanding

**Team T0033** · Blinkit 10-minute grocery delivery database

Blinkit promises delivery in 10 minutes. Every order is served from a nearby **dark store**, a small warehouse with its own stock and prices. The database was built in a hurry, so it has no documented schema, and the 30 most important queries are slow. One of them even gives a wrong answer. The table below shows what each team needs and who suffers when it is slow.

**Real-time** means a person is waiting on a screen right now, so the answer must take milliseconds. **Reporting** means a manager reads a summary later, so a few seconds is fine.

| # | What the business needs (in our words) | Who is affected (stakeholders) | Type | Queries |
|---|---|---|---|---|
| **P1** | As soon as the app opens, find the **nearest open dark store**, then show its **category pages, search results, product stock and cart prices** at once. Any delay eats into the 10 minutes. | Customer | **Real-time** | R01–R05 |
| **P2** | Customers must see **where their order is** right now, and **checkout** (stock check + placing the order) must not slow down at peak hours. | Customer, support | **Real-time** | R06, W01 |
| **P3** | The store's screens must show **open orders** at once, **give each order to a free rider**, and **reduce stock** right after packing. If they lag, packers and riders stand idle. | Dark-store manager, picker/packer, rider | **Real-time** | R07, R21, W02, W03 |
| **P4** | The supply team needs the **low-stock list**, the **restocks of the last week** and the **dead stock** (items that don't sell) every hour, plus a fast **nightly top-up**. | Supply chain / replenishment, store manager | **Real-time / operational** (runs every hour on store screens) | R09, R18, R24, W04 |
| **P5** | The **"products never used as a substitute this month"** list is **always empty**. That's a **wrong answer**, not a speed problem. The cause is a NULL trap in the SQL (`NOT IN` over a column that is mostly NULL). | Category team | **Reporting** (wrong result) | R13 |
| **P6** | **Operations reports** time out: late-delivery % (SLA), **fill rate** (lines delivered short), **wastage** (damage/expiry), **rider speed** and **orders per hour** for staff planning. | Operations, store manager, rider manager | **Reporting / analytics** | R08, R10, R11, R14, R15 |
| **P7** | **Growth and finance reports** are slow: customer cohorts, small-cart fees, daily GMV, top loyal customers, "bought together" recommendations, category sales, the support console's order list and old-data clean-up. Orders will grow **20×**, so these must keep working at scale. | Growth, finance, category team, support | **Reporting / analytics** (+ a batch job) | R12, R16, R17, R19, R20, R22, R23, R25, W05 |

### Summary of the query groups (these set our speed targets later)
- **Real-time (customer and store screens), under 5 ms:** R01–R07, R09, R21, R23, W01–W04
- **Interactive tools, under 250 ms:** R11, R12, R13, R15, R18, R22, R24
- **Reports, under 5 s:** R08, R10, R14, R16, R17, R19, R20, R25
- **Batch job, under 1 s:** W05 (delete old inventory movements)

> R23 (look up a product by SKU) is listed under P7, but it is used by the warehouse **scanner**, so we treat it as real-time. R22 (support console) is interactive.

### Assumptions
1. The CSV exports are the **real production data**. The schema must accept every row. Rows that look wrong are kept and reported as data problems, never deleted.
2. All timestamps are Indian time (**+05:30**). "June 2026" means 1 June 00:00 to 30 June 23:59:59 IST.
3. Data covers **1 Jan 2025 to 30 Jun 2026**. "Today" for the reports is **30 June 2026**.
4. An order belongs to **one store**, and only that store's riders deliver it. A customer can order from any store.
5. A **substitute** is a different product given when the ordered one ran out. It must be stocked by the same store.
6. The 30 queries are fixed. We can only change the schema, the indexes, and rewritten copies of the queries, never the data or server settings.
7. Real-time queries are judged on single-user speed on our laptop (MacBook Pro M4, PostgreSQL 17.10). We are not load testing.
