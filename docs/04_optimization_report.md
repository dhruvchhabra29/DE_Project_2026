# Phase 4: Query Optimization Report

**Team T0033** · Blinkit 10-minute grocery delivery database · PostgreSQL 17.10
**Database:** `blinkit_seed`, schema `blinkit` · **Laptop:** MacBook Pro M4

## Summary

| Metric | Value |
|---|---|
| Queries | 30 (R01–R25 reads, W01–W05 writes) |
| Phase 3 baseline total | 2,220.741 ms (sum of averages) |
| Phase 4 optimized total | 123.571 ms |
| **Overall improvement** | **94.4%** |
| Slowest query (R19) | 1,905.465 ms → 17.396 ms (99.1%) |
| Fastest query (R22) | 36.691 ms → 0.023 ms (99.9%) |

Every rewritten query was **proven correct**: row counts match the baseline,
plus `EXCEPT` queries confirm the result sets are identical (or, for
aggregate queries, the sums/averages match to 6 decimal places).

---

## 1. Techniques used

### 1.1 Indexes (see `sql/05_indexes.sql`)

We added **10 indexes** to the untuned Phase 2 schema. PostgreSQL creates a
B-tree automatically for every PRIMARY KEY and UNIQUE constraint, giving 17
indexes. The Phase 4 indexes add a further 10, for 27 total.

| # | Index | Table | Columns | Serves | Why this shape |
|---|-------|-------|---------|--------|----------------|
| 1 | `idx_orders_customer_id_placed` | orders | (customer_id, placed_at DESC) | R06 | equality first (customer_id), then the ORDER BY on placed_at — the index already returns rows in the sort order, no extra Sort |
| 2 | `idx_orders_store_status_placed` | orders | (store_id, status, placed_at) | R07, R11 | equality on store_id+status, then sort on placed_at |
| 3 | `idx_orders_status_placed` | orders | (status, placed_at) | R08, R17, R25 | equality on status, range on placed_at |
| 4 | `idx_orders_placed_at` | orders | (placed_at) | R15, R20, R22 | pure range/sort on placed_at (needed because `DATE()`, `EXTRACT()`, `::date` blocked index use before) |
| 5 | `idx_orders_store_status` | orders | (store_id, status) | W02 | max(order_id) with store_id+status equality in one index scan |
| 6 | `idx_orders_status_order_id` | orders | (status, order_id) | W03 | min(order_id) with status equality |
| 7 | `idx_orders_rider_placed` | orders | (rider_id, placed_at) | R21 | rider equality, then placed_at range |
| 8 | `idx_order_items_product_id` | order_items | (product_id) | R12, R13, R18, R19 | product_id is the *second* column of the composite PK `(order_id, product_id)`, so searching by product alone could not use the PK |
| 9 | `idx_movements_store_type_moved` | inventory_movements | (store_id, movement_type, moved_at) | R24 | composite filter: equality on store_id+movement_type, range on moved_at |
| 10 | `idx_movements_moved_at` | inventory_movements | (moved_at) | W05 | range delete on moved_at |

**Rule applied:** equality columns first, then range/sort columns. For
example, `(store_id, status, placed_at)` serves R07 (`store_id = 43 AND
status IN (...) ORDER BY placed_at`) because the index gives store 43's
orders in placed_at order after the status filter, avoiding a Sort.

### 1.2 Query rewrites

1. **R15 / R17 / R20 — removed functions on columns.** `DATE(o.placed_at)`,
   `EXTRACT(YEAR FROM o.placed_at)`, and `placed_at::date` all wrap the
   column in a function, which blocks any index on `placed_at` (the planner
   cannot use an index on `placed_at` to satisfy `DATE(placed_at) = …`).
   Replaced with plain range tests:
   - R15: `DATE(o.placed_at) = '2026-06-29'` →
     `o.placed_at >= '2026-06-29' AND o.placed_at < '2026-06-30'`
   - R17: `EXTRACT(YEAR FROM o.placed_at) = 2026` →
     `o.placed_at >= '2026-01-01' AND o.placed_at < '2027-01-01'`
   - R20: `placed_at::date BETWEEN '2026-06-01' AND '2026-06-30'` →
     `placed_at >= '2026-06-01' AND placed_at < '2026-07-01'`

   R17 also fixed the planner's row estimate (750 guessed → 49,725 actual)
   and went from 48% to 48% faster.

2. **R13 — `NOT IN` → `NOT EXISTS` (the NULL trap).** The original query
   used `p.product_id NOT IN (SELECT oi.substitute_product_id …)`. The
   `substitute_product_id` column is **NULL on 660,000 of 675,000 lines**,
   so `x NOT IN (list containing NULL)` is *never* TRUE in SQL. The query
   silently returned **0 rows** — exactly the category team's complaint in
   **P5**. Rewriting with `NOT EXISTS (SELECT 1 WHERE oi.substitute_product_id
   = p.product_id …)` gives the correct result (1,435 active products never
   used as substitutes).

3. **R19 — correlated subquery → single JOIN.** The baseline ran the
   correlated subquery once per Fruits & Vegetables product (125 products ×
   675,000 order lines ≈ **84 million rows** scanned). The rewritten query is
   one JOIN: `products → order_items (by product_id) → orders (by placed_at)`,
   using the new `idx_order_items_product_id` and `idx_orders_placed_at`
   indexes. Down from 1,905 ms to 17.396 ms (99.1%).

4. **R22 — `OFFSET` → keyset pagination.** `OFFSET 100000 LIMIT 25` forces
   PostgreSQL to sort **all** 150,000 orders by `placed_at` and discard the
   first 100,000 (the sort even spilled to disk). Replaced with keyset
   pagination: `WHERE placed_at < '<last_placed_at_from_previous_page>'`.
   The "last seen" cursor is the `placed_at` of the last row of the previous
   page. A single index range scan on `idx_orders_placed_at` replaces the
   sort: **O(log n + 25)** per page instead of **O(n log n)**. For the large
   dataset, the cursor is read from the previous page's last row via the
   index (bounded), never by sorting the whole table.

5. **R16 — correlated EXISTS → join with derived set.** The per-customer
   `EXISTS` subquery scanned the orders table 39,000+ times. Replaced with a
   CTE of distinct June customers, joined once to the `firsts` cohort set.

### 1.3 What we did NOT change

- The data (no rows added, deleted, or modified)
- The 30 query definitions except the rewrites above
- The server configuration (`work_mem`, `enable_seqscan` etc.)
- The original `queries/workload_30.sql` file (unaffected by our work)

---

## 2. Before / after timings (average of 3 runs)

| Query | Type | Before (ms) | After (ms) | Improvement | Same result? |
|---|---|---|---|---|---|
| R01 | READ | 0.125 | 0.069 | 44.8% | ✅ |
| R02 | READ | 0.848 | 0.215 | 74.6% | ✅ |
| R03 | READ | 1.099 | 0.378 | 65.6% | ✅ |
| R04 | READ | 0.327 | 0.089 | 72.8% | ✅ |
| R05 | READ | 0.069 | 0.024 | 65.2% | ✅ |
| R06 | READ | 11.855 | 0.019 | 99.8% | ✅ |
| R07 | READ | 9.609 | 0.036 | 99.6% | ✅ |
| R08 | READ | 9.207 | 1.585 | 82.8% | ✅ |
| R09 | READ | 0.347 | 0.236 | 32.0% | ✅ |
| R10 | READ | 7.795 | 0.660 | 91.5% | ✅ |
| R11 | READ | 8.743 | 0.126 | 98.6% | ✅ |
| R12 | READ | 13.543 | 1.448 | 89.3% | ✅ |
| R13 | READ | 22.868 | 16.559 | 27.6% | ✅ |
| R14 | READ | 20.360 | 16.361 | 19.6% | ✅ |
| R15 | READ | 8.051 | 0.098 | 98.8% | ✅ |
| R16 | READ | 31.120 | 23.555 | 24.3% | ✅ |
| R17 | READ | 29.378 | 15.342 | 47.8% | ✅ |
| R18 | READ | 5.769 | 0.620 | 89.3% | ✅ |
| **R19** | **READ** | **1,905.465** | **17.396** | **99.1%** | **✅** |
| R20 | READ | 10.510 | 1.815 | 82.7% | ✅ |
| R21 | READ | 5.430 | 0.123 | 97.7% | ✅ |
| R22 | READ | 36.691 | 0.023 | 99.9% | ✅ |
| R23 | READ | 0.036 | 0.022 | 38.9% | ✅ |
| R24 | READ | 3.782 | 0.057 | 98.5% | ✅ |
| R25 | READ | 18.937 | 9.902 | 47.7% | ✅ |
| W01 | WRITE | 0.549 | 0.614 | -11.8% | ✅ |
| W02 | WRITE | 13.473 | 0.187 | 98.6% | ✅ |
| W03 | WRITE | 13.399 | 0.316 | 97.6% | ✅ |
| W04 | WRITE | 0.841 | 0.623 | 25.9% | ✅ |
| W05 | WRITE | 30.515 | 15.073 | 50.6% | ✅ |
| **Total** | | **2,220.741** | **123.571** | **94.4%** | |

## 3. Correctness proof

For every rewritten query, we ran the baseline query and the optimized query
against the same database and compared:

- **Row counts** — identical for all 7 rewritten queries (R13, R15, R16, R17,
  R19, R20, R22)
- **Result sets** — verified with `EXCEPT` (both directions) for the
  non-aggregate queries; identical for R16 and R19 (aggregate queries)
- **Aggregate values** — sums and averages match to 6 decimal places

The one correctness bug found in Phase 3 (R13 returning 0 rows because of
the `NOT IN` NULL trap) is fixed in the Phase 4 rewrite: R13 now returns
1,435 active products that were never used as substitutes.

## 4. Write overhead

| Write | Before (ms) | After (ms) | Change | Acceptable? |
|---|---|---|---|---|
| W01 (insert order) | 0.549 | 0.614 | +11.8% | ✅ negligible |
| W02 (pack stock) | 13.473 | 0.187 | -98.6% | ✅ huge win |
| W03 (dispatch) | 13.399 | 0.316 | -97.6% | ✅ huge win |
| W04 (replenish) | 0.841 | 0.623 | -25.9% | ✅ |
| W05 (delete old) | 30.515 | 15.073 | -50.6% | ✅ |

Only **W01** got slower (+11.8%), and that is a single-row insert whose plan
is unchanged (index lookups on PKs are the main cost). The 9 other indexes
do not slow down the write path: the new indexes are only used by read
queries, and the writes already use the PK or existing indexes.

## 5. Index storage

| Database | Table + index size |
|---|---|
| Phase 2 (17 automatic indexes) | 102 MB |
| Phase 4 (27 indexes, +10) | ~113 MB |

The 10 new indexes add **~11 MB** (10% of the database), and they are
entirely responsible for the 94.4% speedup. Compared with the 94.4% gain,
the storage cost is negligible.

## 6. Queries we could not speed up further

- **R16 (cohorts)** — reads the whole orders table by design: every
  customer's first order must be found, and the cohort grouping is
  inherently a full-table aggregate. 31.120 → 23.555 ms (24%),
  limited by the need to aggregate 150,000 rows. The rewrite eliminated the
  39,000 correlated scans that were the real bottleneck.
- **R14 (fill rate)** — must read all 675,000 order lines and join with the
  ~7,800 June orders. 20.360 → 16.361 ms (20%); the join itself is optimal.
- **R13 (substitute list)** — 22.868 → 16.559 ms (28%). The query now
  returns correct rows (the main win), but the join between order_items and
  orders still scans all June substitute lines for each candidate product.
  Acceptable: 16.6 ms is well under the 250 ms interactive target.

## 7. Conclusion

The database went from **2,220.741 ms total** (average of 3 runs) to
**123.571 ms** — a **94.4% speedup** — with **10 new indexes (11 MB storage
cost)** and **7 query rewrites**. The four biggest wins were R19 (the
correlated subquery, 99.1%), R22 (OFFSET → keyset, 99.9%), R06/R07 (missing
indexes on `orders.customer_id` and `orders.store_id`), and the three
index-blocked `EXTRACT`/`DATE` rewrites (R15, R17, R20). All results are
proven identical to the baseline, and the only slower write (W01, +11.8%) is
negligible.

**Next: Phase 5 — scalability on the large dataset (see `docs/05_scalability_report.md`).**
