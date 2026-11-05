# Phase 3: Baseline Timings

**Team T0033** · Blinkit 10-minute grocery delivery database

This is how fast the 30 workload queries run on our Phase 2 schema **before any tuning**. The only indexes are the 17 that PostgreSQL creates automatically for PRIMARY KEY and UNIQUE constraints. These numbers are the "before" side of every comparison in Phase 4.

## How we measured

| Item | Value |
|---|---|
| Laptop | MacBook Pro M4 (the same laptop will be used for Phase 4) |
| Database | PostgreSQL 17.10 (Homebrew), database `blinkit_seed`, schema `blinkit` |
| Data | Seed data: 150,000 orders · 675,000 order items · 126,000 stock rows |
| State | Fresh rebuild with `sql/01_schema.sql` + `sql/02_load_data.sql` (which ends with `ANALYZE`). No VACUUM and no extra indexes, because those are Phase 4 techniques. |
| Command | `./benchmarks/run_benchmark.sh blinkit_seed baseline` |
| Method | Each query runs with `EXPLAIN (ANALYZE, BUFFERS)` **3 times**. We read the `Execution Time` line of each run and report the **average** of the 3. |
| Writes | W01–W05 run inside `BEGIN; … ROLLBACK;`, so the data never changes |
| Queries | `queries/workload_30.sql`, unchanged |
| Raw plans | [`benchmarks/results/baseline/`](../benchmarks/results/baseline/): `R01.txt` … `W05.txt` hold all 3 plans of each query; [`summary.csv`](../benchmarks/results/baseline/summary.csv) holds avg / median / min / max |

Every number below is copied by a script from the `Execution Time` lines in those raw files. The script also checks that each average equals `avg_ms` in `summary.csv`.

## Timing table (all 30 queries)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Store assignment: the nearest active dark store within ~3 km of a customer at (12.93, 77.62) | READ | 0.119 | 0.112 | 0.143 | **0.125** |
| R02: Category page: Dairy products in stock at store 43, cheapest first | READ | 0.870 | 0.758 | 0.915 | **0.848** |
| R03: Search: products with "milk" in the name that are in stock at store 43 | READ | 0.966 | 1.099 | 1.232 | **1.099** |
| R04: Product page: stock of product 1236 in every Bengaluru dark store | READ | 0.350 | 0.331 | 0.299 | **0.327** |
| R05: Cart check: current stock and price of 4 cart items at store 43 | READ | 0.067 | 0.070 | 0.071 | **0.069** |
| R06: Order tracking: customer 1027's latest order with its timeline | READ | 17.612 | 8.961 | 8.991 | **11.855** |
| R07: Store screen: open orders at store 43 (not yet delivered or cancelled) | READ | 12.368 | 8.263 | 8.196 | **9.609** |
| R08: SLA report: share of June 2026 deliveries that took longer than promised, per store | READ | 9.071 | 9.816 | 8.733 | **9.207** |
| R09: Replenishment: products at store 43 at or below their reorder level | READ | 0.521 | 0.272 | 0.249 | **0.347** |
| R10: Wastage: units lost to expiry or damage per category in June 2026 | READ | 11.461 | 5.544 | 6.381 | **7.795** |
| R11: Rider performance: average minutes from pickup to delivery per rider at store 43 (June 2026) | READ | 8.397 | 8.353 | 9.479 | **8.743** |
| R12: Recommendations: products most often bought together with product 1236 | READ | 21.898 | 8.656 | 10.076 | **13.543** |
| R13: Category team: active products that were never given as a substitute in June 2026 | READ | 23.454 | 23.173 | 21.976 | **22.868** |
| R14: Fill rate: share of order lines delivered short, per store, June 2026 | READ | 19.986 | 20.369 | 20.724 | **20.360** |
| R15: Staffing: orders per hour at Bengaluru stores on 29 June 2026 | READ | 8.352 | 7.971 | 7.830 | **8.051** |
| R16: Growth: monthly cohorts—customers by month of first order, and how many ordered again in June 2026 | READ | 31.278 | 31.540 | 30.541 | **31.120** |
| R17: Finance: small-cart fee collected per city per month in 2026 | READ | 29.761 | 28.702 | 29.670 | **29.378** |
| R18: Dead stock: products in stock at store 43 that did not sell there in June 2026 | READ | 5.899 | 5.867 | 5.540 | **5.769** |
| R19: Category report: June 2026 units sold of every Fruits & Vegetables product | READ | 1867.387 | 1910.616 | 1938.391 | **1905.465** |
| R20: Finance: daily GMV and running total for June 2026 | READ | 11.211 | 10.564 | 9.754 | **10.510** |
| R21: Store manager: active riders of store 43 with no delivery on 30 June 2026 | READ | 5.564 | 5.421 | 5.306 | **5.430** |
| R22: Support console: all orders, newest first, page 4,001 (25 per page) | READ | 36.807 | 35.672 | 37.593 | **36.691** |
| R23: Warehouse scanner: look up a product by SKU | READ | 0.037 | 0.034 | 0.036 | **0.036** |
| R24: Supply chain: units restocked per product at store 43 in the last 7 days of June 2026 | READ | 3.752 | 3.329 | 4.264 | **3.782** |
| R25: Loyalty: 20 Mumbai customers with the most delivered orders in 2026 | READ | 21.446 | 18.567 | 16.797 | **18.937** |
| W01: Checkout: place a new order at store 43 | WRITE | 0.656 | 0.499 | 0.493 | **0.549** |
| W02: Packing done: reduce store 43's stock for every line of its most recent PLACED or PACKING order | WRITE | 14.269 | 13.311 | 12.839 | **13.473** |
| W03: Dispatch: give the oldest PACKING order (anywhere) to its store's first active rider | WRITE | 13.392 | 13.442 | 13.362 | **13.399** |
| W04: Nightly replenishment at store 43: top up everything at or below reorder level | WRITE | 1.170 | 0.723 | 0.630 | **0.841** |
| W05: Data retention: delete inventory movements older than 1 January 2026 | WRITE | 62.360 | 15.363 | 13.821 | **30.515** |
| **Total (sum of all 30)** | | **2240.481** | **2197.398** | **2224.332** | **2220.741** |

## What the numbers say

| Group | Queries | Average time |
|---|---|---|
| 🐢 **Very slow** | **R19** | **1,905 ms**, alone **86% of the total** |
| Slow (10–40 ms) | R22, R16, W05, R17, R13, R14, R25, R12, W02, W03, R06, R20 | 10.5 – 36.7 ms |
| Medium (3–10 ms) | R07, R08, R11, R15, R10, R18, R21, R24 | 3.8 – 9.6 ms |
| Fast (under 1.2 ms) | R01, R02, R03, R04, R05, R09, R23, W01, W04 | 0.036 – 1.099 ms |

- **R19 is the query the README warns about** ("noticeably longer than the others"). Section *Scan type and reason* explains why.
- **Run 1 is often slower than runs 2 and 3.** Examples: R06 17.6 → 9.0 → 9.0 ms, R12 21.9 → 8.7 → 10.1 ms, W05 62.4 → 15.4 → 13.8 ms. In run 1, some pages must come from disk into PostgreSQL's memory (its *shared buffers*). Runs 2 and 3 find them already there (`Buffers: shared hit`). That's why the method averages 3 runs instead of trusting one.
- **R13 returns 0 rows.** It's fast (22.9 ms), but its answer is wrong (the NULL trap, see the design doc §7.1). It gets fixed in Phase 4.
