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

---

## Scan type and reason for each query

**How to read a scan type:**
- **Seq Scan**: PostgreSQL reads *every row* of the table and throws away the ones that don't match. Fine for tiny tables, slow for big ones.
- **Parallel Seq Scan**: the same, but split across 2–3 worker processes.
- **Index Scan**: it jumps straight to the matching rows through a B-tree index, then reads those rows.
- **Index Only Scan**: the index alone holds every column needed, so the table itself isn't touched.
- **Bitmap Index Scan → Bitmap Heap Scan**: it first collects all matching row addresses from the index, then reads those table pages in order. Used for a medium number of rows.

Scan types are from the plan of each query (all 3 runs used the same plan). "Rows removed" is the plan's *Rows Removed by Filter*: rows that were read and then thrown away.

| Query | Avg (ms) | Scan type(s) in the plan | Why it is slow or fast |
|---|---:|---|---|
| R01 | 0.125 | Seq Scan on dark_stores | Only 120 stores (5 pages). Reading them all and keeping the 1 inside the lat/long box is cheaper than using any index. |
| R02 | 0.848 | Seq Scan on products and categories (Hash Join) → Index Scan on store_inventory_pkey (125 loops) | Scans all 1,500 products to find the 125 Dairy ones, then does one primary-key lookup (store 43, product) for each. Small tables keep it fast. |
| R03 | 1.099 | Seq Scan on products (ILIKE) → Index Scan on store_inventory_pkey (31 loops) | `ILIKE '%milk%'` starts with a wildcard, so a normal B-tree can't help. Every product name is read (1,469 removed, 31 match). |
| R04 | 0.327 | Seq Scan on dark_stores → Index Scan on store_inventory_pkey (19 loops) | Fast: for each of the 19 Bengaluru stores, it looks up the pair (store_id, 1236) directly in the 2-column primary key. |
| R05 | 0.069 | Index Scan on store_inventory_pkey | `store_id = 43 AND product_id IN (…)` matches the 2-column primary key exactly. Already optimal. |
| R06 | 11.855 | Seq Scan on orders | **No index on `customer_id`.** Reads all 150,000 orders to find this customer's 9 (149,991 removed), then sorts to get the latest one. |
| R07 | 9.609 | Parallel Seq Scan on orders | No index on `store_id` or `status`. Reads all 150,000 orders to find 4 open ones at store 43. |
| R08 | 9.207 | Parallel Seq Scan on orders | No index on `placed_at`. Reads every order to keep the 7,816 June deliveries (about 5%), then groups them by store. |
| R09 | 0.347 | Bitmap Index Scan on store_inventory_pkey → Bitmap Heap Scan; Seq Scan on products | `store_id` is the *first* column of the primary key, so the store's 1,050 rows are found in just 8 pages. The filter keeps the 229 low-stock rows. |
| R10 | 7.795 | Seq Scan on inventory_movements; Seq Scan on products; Index Scan on categories_pkey | No index on `movement_type` or `moved_at`. Reads all 90,000 movements to keep 570 June damage/expiry rows. |
| R11 | 8.743 | Parallel Seq Scan on orders | Reads all 150,000 orders to find store 43's 68 June deliveries (no index on `store_id` + `placed_at`). |
| R12 | 13.543 | Parallel Seq Scan on order_items → Index Only Scan on order_items_pkey (466 loops) | To find the orders containing product 1236, it must read all 675,000 lines, because `product_id` is only the *second* column of the primary key. The "other products" lookup is cheap because it uses `order_id`, the first column. |
| R13 | 22.868 | Seq Scan on products; Parallel Seq Scan on order_items and orders (Hash Join), hashed SubPlan | Builds the list of 37,086 June substitute values, most of them NULL, and tests every product with `NOT IN`. **Returns 0 rows**, which is the NULL trap, not a speed problem. |
| R14 | 20.360 | Parallel Seq Scan on order_items and orders (Parallel Hash Join) | Reads all 675,000 order lines to join them with the 8,241 June orders, because there's no index to find June orders first. |
| R15 | 8.051 | Seq Scan on orders → Memoize + Index Scan on dark_stores_pkey | `DATE(placed_at) = '2026-06-29'` wraps the column in a function, so even an index on `placed_at` couldn't be used. Reads 150,000 rows to keep 275. |
| R16 | 31.120 | Seq Scan on orders (twice: HashAggregate + hashed SubPlan) | It groups **all** 150,000 orders by customer (39,011 groups) to find first orders, so it reads the whole table by design. PostgreSQL turned the per-customer `EXISTS` into one hashed list, which keeps it at 31 ms. |
| R17 | 29.378 | Seq Scan on orders → Memoize + Index Scan on dark_stores_pkey | `EXTRACT(YEAR FROM placed_at) = 2026` is a function on the column: no index can be used, and the planner **guessed 750 rows but got 49,725** (66× off). |
| R18 | 5.769 | Seq Scan on orders; Index Only Scan on order_items_pkey; Bitmap scans on store_inventory; Seq Scan on products | Reads all 150,000 orders to find store 43's 74 June orders. Everything after that uses primary keys and is cheap. |
| **R19** | **1,905.465** | Seq Scan on products → **Seq Scan on order_items repeated 125 times** → Index Scan on orders_pkey (56,292 loops) | **The slowest query.** The units-sold subquery is *correlated* (it depends on `p.product_id`), so it runs once per Fruits & Vegetables product. Each run reads all 675,000 order lines: 125 × 675,000 ≈ **84 million rows**. |
| R20 | 10.510 | Parallel Seq Scan on orders | `placed_at::date BETWEEN …` casts the column, which blocks index use. Reads all orders to keep 7,816 June deliveries. |
| R21 | 5.430 | Seq Scan on orders + Seq Scan on riders (Hash Right Anti Join) | No index on `orders.placed_at` or `rider_id`. Reads all orders to find the 274 on 30 June, and all 1,800 riders to find store 43's 14 active ones. |
| R22 | 36.691 | Seq Scan on orders → top-N heapsort | `OFFSET 100000` forces PostgreSQL to sort **all 150,000 orders** by `placed_at`, then throw away the first 100,000 to return 25. The second-slowest read query. |
| R23 | 0.036 | Index Scan on products_sku_key | The UNIQUE constraint on `sku` created a B-tree index, so this is one jump. Already optimal. |
| R24 | 3.782 | Seq Scan on inventory_movements | No index on `store_id` or `moved_at`. Reads 90,000 movements to keep 7. |
| R25 | 18.937 | Seq Scan on orders + Seq Scan on customers (Hash Join) | Reads all orders (keeps the 47,725 delivered in 2026) and all customers (keeps the 6,400 in Mumbai), then joins and groups them. A report that needs about a third of the orders anyway. |
| W01 | 0.549 | none (single-row Insert) | One insert. The plan shows 3 *Trigger for constraint* lines: that's PostgreSQL checking the 3 foreign keys (customer, store, rider) through their primary keys. |
| W02 | 13.473 | Seq Scan on orders (InitPlan) → Index Scan on order_items_pkey and store_inventory_pkey | **12.6 of the 12.8 ms** is spent finding store 43's latest PLACED/PACKING order by reading all 150,000 orders. The stock update itself (5 rows, by primary key) is instant. |
| W03 | 13.399 | Index Scan on orders_pkey (walk) → Index Scan on riders_pkey | `min(order_id) WHERE status = 'PACKING'` walks the `order_id` index from order 1 and throws away 149,895 orders before reaching the first PACKING one, because they're all from 30 June, at the very end. |
| W04 | 0.841 | Bitmap Index Scan on store_inventory_pkey → Bitmap Heap Scan | Uses `store_id`, the leading column of the primary key, to find store 43's rows, then updates the 229 low-stock ones. |
| W05 | 30.515 | Seq Scan on inventory_movements | Deletes 60,165 of 90,000 rows (two-thirds of the table), so reading the whole table is the right plan. Run 1 was 62 ms because the pages weren't in memory yet; runs 2 and 3 took about 14 ms. |

## Summary of the baseline

- **25 of 30 queries use at least one Seq Scan.** Only R05, R23, W01, W03 and W04 avoid one, because they can use the automatic primary-key or UNIQUE indexes.
- **15 queries read the entire `orders` table:** R06, R07, R08, R11, R13, R14, R15, R16, R17, R18, R20, R21, R22, R25 and W02. The cause is that PostgreSQL does **not** index foreign-key or filter columns automatically (`customer_id`, `store_id`, `placed_at`, `status`).
- **4 queries read the entire `order_items` table:** R12, R13, R14 and R19. `product_id` is the second column of its primary key, so the key can't be used to search by product.
- **3 queries put a function on `placed_at`** (R15 `DATE()`, R17 `EXTRACT(YEAR)`, R20 `::date`). That blocks any index and, in R17, ruins the row estimate.
- **R19 alone takes 86% of the total time**, because of its correlated subquery.
- **R13 is fast but wrong** (0 rows).

These findings are the starting list for Phase 4: indexes on `orders` and `order_items(product_id)`, rewriting R15/R17/R20 as plain date ranges, turning R19 into a single join, keyset pagination for R22, and `NOT EXISTS` for R13.
