-- =====================================================================
-- sql/08_partitioning.sql : Phase 5 partitioning DDL for order_items
-- =====================================================================
-- Run on the large database. Handles partially-completed state gracefully.
-- Data range: 2028-01 to 2030-12 (156 monthly partitions).
-- =====================================================================

-- Step 1: Drop PK if exists (idempotent)
DO $$
BEGIN
    ALTER TABLE blinkit.order_items
        DROP CONSTRAINT IF EXISTS order_items_pkey CASCADE;
END $$;

-- Step 2: Remove placed_at column (if exists from previous run)
ALTER TABLE blinkit.order_items
    DROP COLUMN IF EXISTS placed_at;

-- Step 3: Add placed_at column and populate from orders
ALTER TABLE blinkit.order_items
    ADD COLUMN placed_at TIMESTAMPTZ NOT NULL
    DEFAULT '2026-01-01 00:00:00+00';

UPDATE blinkit.order_items oi
SET placed_at = o.placed_at
FROM blinkit.orders o
WHERE oi.order_id = o.order_id;

-- Step 4: Create partitioned table (shell)
DROP TABLE IF EXISTS blinkit.order_items_partitioned;

CREATE TABLE blinkit.order_items_partitioned (
    LIKE blinkit.order_items INCLUDING ALL
) PARTITION BY RANGE (placed_at);

-- Step 5: Add PK with all partitioning columns
ALTER TABLE blinkit.order_items_partitioned
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (order_id, product_id, placed_at);

-- Step 6: Create monthly partitions (2028-01 to 2030-12, 36 partitions)
-- Using a simple DO block with dynamic SQL
DO $$
DECLARE
    ddl_text TEXT;
    s_date TEXT;
    e_date TEXT;
    y INTEGER;
    m INTEGER;
BEGIN
    FOR y IN 2028..2030 LOOP
        FOR m IN 1..12 LOOP
            s_date := to_char(to_timestamp(y || '-' || to_char(m, 'FM00') || '-01', 'YYYY-MM-DD TZH') , 'YYYY-MM-DD');
            e_date := to_char(to_timestamp(y || '-' || to_char(m, 'FM00') || '-01', 'YYYY-MM-DD TZH') + interval '1 month', 'YYYY-MM-DD');
            ddl_text := 'CREATE TABLE blinkit.order_items_' || y || '_' || to_char(m, 'FM00') || ' PARTITION OF blinkit.order_items_partitioned '
                      || 'FOR VALUES FROM (''' || s_date || ''') TO (''' || e_date || ''')';
            EXECUTE ddl_text;
        END LOOP;
    END LOOP;
END $$;

-- Step 7: Insert data into partitioned table (long-running, ~4-6 min)
INSERT INTO blinkit.order_items_partitioned
SELECT * FROM blinkit.order_items;

-- Step 8: Drop original order_items
DROP TABLE blinkit.order_items;

-- Step 9: Rename partitioned table to order_items
ALTER TABLE blinkit.order_items_partitioned RENAME TO order_items;

-- Step 10: Show partition pruning
\echo '=== Partition summary ==='
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
WHERE tablename LIKE 'order_items_partitioned%'
   OR tablename = 'order_items'
ORDER BY tablename;

\echo '=== Total rows in partitioned table ==='
SELECT count(*) as total_rows FROM blinkit.order_items;

\echo '=== Number of partitions ==='
SELECT count(*) as partition_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'p'
  AND n.nspname = 'blinkit'
  AND c.relname LIKE 'order_items\_%';

\echo '=== EXPLAIN for R19 on partitioned order_items (June 2026) ==='
EXPLAIN (COSTS OFF)
SELECT p.product_id, p.product_name,
       COALESCE(SUM(oi.quantity_delivered), 0) AS units_sold
FROM blinkit.products p
JOIN blinkit.categories c ON c.category_id = p.category_id
       AND c.category_name = 'Fruits & Vegetables'
LEFT JOIN blinkit.order_items oi
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
