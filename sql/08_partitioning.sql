-- =====================================================================
-- Blinkit DBMS Project · Team T0033
-- sql/08_partitioning.sql : Phase 5 partitioning DDL for order_items
--
-- Run on the large-database after 01_schema.sql, 02_load_data.sql,
-- 05_indexes.sql and ANALYZE. The large data lives in the table
-- blinkit.order_items (13.5M rows). Partitioning by time is what makes
-- the queries fast at 20x scale.
--
-- Why partition order_items?
--   order_items is the biggest table at scale (13.5M rows; ~2,520,000 stock
--   rows; 1.8M inventory movements). Every time-based query (R19, R14, R19,
--   R24, W05) filters on placed_at / moved_at. A partitioned table lets the
--   planner visit only the relevant months, cutting both I/O and the plan
--   time by roughly the fraction of the year in the filter.
--
-- Partitioning choice: RANGE on placed_at (monthly partitions).
--   RANGE is the right choice because the queries filter on DATE(placed_at),
--   EXTRACT(YEAR FROM placed_at) and month boundaries, and the data is
--   already inserted in time order (the CSV is sorted by order_id, which is
--   chronological in this export). A monthly partition is a good balance:
--   not too many, not too big, and every query can use a single partition.
--
-- The PK rule for partitioned tables (PostgreSQL requirement):
--   The PRIMARY KEY must include EVERY column used for partitioning.
--   Since we partition by placed_at, the PK is:
--     PRIMARY KEY (order_id, product_id, placed_at)
--   This is the only way PostgreSQL allows a UNIQUE index on a partitioned
--   table. The downside: order_items_pkey (order_id, product_id) no longer
--   works; the new key (order_id, product_id, placed_at) is a superset.
--
-- =====================================================================

-- --- Step 1: add the time column to order_items (copy from orders) ---
-- A real deployment would fill this via a trigger or a batch job. For the
-- large dataset we copy it from the orders table after loading.
ALTER TABLE blinkit.order_items
    ADD COLUMN placed_at TIMESTAMPTZ NOT NULL
    DEFAULT '2026-01-01 00:00:00+00';

-- --- Step 2: build the partitioned table ---
-- The partitioned table is a shell: no rows live here. All data goes into
-- the monthly child partitions.
DROP TABLE IF EXISTS blinkit.order_items_partitioned;
CREATE TABLE blinkit.order_items_partitioned (
    LIKE blinkit.order_items INCLUDING ALL
) PARTITION BY RANGE (placed_at);

-- --- Step 3: create monthly partitions ---
-- We create one partition per month from 2025-01 to 2026-07.
-- Partition names: order_items_<YYYY>_<MM>
SELECT 'CREATE TABLE blinkit.order_items_2025_01 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-01-01'') TO (''2025-02-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_02 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-02-01'') TO (''2025-03-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_03 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-03-01'') TO (''2025-04-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_04 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-04-01'') TO (''2025-05-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_05 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-05-01'') TO (''2025-06-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_06 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-06-01'') TO (''2025-07-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_07 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-07-01'') TO (''2025-08-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_08 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-08-01'') TO (''2025-09-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_09 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-09-01'') TO (''2025-10-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_10 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-10-01'') TO (''2025-11-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_11 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-11-01'') TO (''2025-12-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2025_12 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2025-12-01'') TO (''2026-01-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2026_01 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2026-01-01'') TO (''2026-02-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2026_02 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2026-02-01'') TO (''2026-03-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2026_03 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2026-03-01'') TO (''2026-04-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2026_04 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2026-04-01'') TO (''2026-05-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2026_05 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2026-05-01'') TO (''2026-06-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2026_06 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2026-06-01'') TO (''2026-07-01'')'
     AS ddl
UNION ALL SELECT 'CREATE TABLE blinkit.order_items_2026_07 PARTITION OF blinkit.order_items_partitioned '
     || 'FOR VALUES FROM (''2026-07-01'') TO (''2026-08-01'')'
     AS ddl;

-- --- Step 4: show partition pruning with EXPLAIN ---
-- The query filters on placed_at in June 2026, so only
-- blinkit.order_items_2026_06 should be touched.
\echo '=== EXPLAIN for R19 on partitioned order_items (June 2026) ==='
EXPLAIN (COSTS OFF)
SELECT p.product_id, p.product_name,
       coalesce(SUM(oi.quantity_delivered), 0) AS units_sold
FROM blinkit.products p
JOIN blinkit.categories c ON c.category_id = p.category_id
       AND c.category_name = 'Fruits & Vegetables'
LEFT JOIN blinkit.order_items_partitioned oi
       ON oi.product_id = p.product_id
      AND oi.placed_at >= '2026-06-01' AND oi.placed_at < '2026-07-01'
LEFT JOIN blinkit.orders o
       ON o.order_id = oi.order_id
      AND o.placed_at >= '2026-06-01' AND o.placed_at < '2026-07-01'
WHERE p.category_id = (SELECT category_id FROM blinkit.categories WHERE category_name = 'Fruits & Vegetables')
GROUP BY p.product_id, p.product_name
ORDER BY units_sold DESC;

\echo '=== EXPLAIN for R24 on partitioned order_items (store 43, June 2026) ==='
EXPLAIN (COSTS OFF)
SELECT m.product_id, count(*) AS restocks, sum(m.quantity) AS units
FROM blinkit.inventory_movements m
WHERE m.store_id = 43 AND m.movement_type = 'RESTOCK'
  AND m.moved_at >= '2026-06-24'
GROUP BY m.product_id
ORDER BY units DESC;

\echo '=== Partition counts (all months) ==='
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
WHERE tablename LIKE 'order_items%'
ORDER BY tablename;

-- =====================================================================
-- END OF FILE
-- =====================================================================
