-- =====================================================================
-- Blinkit DBMS Project · Team T0033
-- sql/05_indexes.sql : Phase 4 indexes
--
-- Run ON TOP of the Phase 2 schema (after sql/01_schema.sql and 02_load_data.sql)
-- on the same database:
--   psql -d blinkit_seed -v ON_ERROR_STOP=1 -f sql/05_indexes.sql
--
-- Rules we follow (README Phase 4):
--   * Every index is justified: which query it serves and WHY this type/column
--     order. Equality columns first, then range/sort columns.
--   * The only changes to the 30 queries are in sql/06_optimized_queries.sql.
--   * The results must stay the SAME for every rewritten query.
-- =====================================================================

-- -----------------------------------------------------------------
-- Orders: the workhorse index for 6 queries (R06, R07, R08, R11, R15,
-- R17, R20, R21, R22, R25). An equality column first, then a sort/range
-- column, so the index can both filter AND sort without a separate Sort.
-- -----------------------------------------------------------------

-- R06: equality on customer_id, then placed_at (for ORDER BY DESC LIMIT 1)
--   Index scan: (customer_id) equality
--   ORDER BY placed_at DESC is already in the index order
--   (customer_id, placed_at) is a covering-ish index for the SELECT.
CREATE INDEX idx_orders_customer_id_placed
    ON blinkit.orders (customer_id, placed_at DESC);

-- R07 / R11: equality on store_id, then status (filter), then placed_at
--   (store_id, status, placed_at) gives store's orders in placed_at order
--   after the status filter, so no extra Sort for ORDER BY placed_at.
CREATE INDEX idx_orders_store_status_placed
    ON blinkit.orders (store_id, status, placed_at);

-- R08: equality on status, then range on placed_at
--   (status, placed_at) is used for the filter; the GROUP BY store_id
--   still needs a Sort, but the full table scan is gone.
CREATE INDEX idx_orders_status_placed
    ON blinkit.orders (status, placed_at);

-- R15 / R20 / R22: pure range/sort on placed_at
--   (placed_at) is used for the range filter and the ORDER BY.
CREATE INDEX idx_orders_placed_at
    ON blinkit.orders (placed_at);

-- W02: subquery finds max(order_id) with store_id + status equality.
--   (store_id, status) lets the planner scan only store 43's PLACED/PACKING
--   orders and take the max from the index tail.
CREATE INDEX idx_orders_store_status
    ON blinkit.orders (store_id, status);

-- W03: subquery finds min(order_id) with status equality.
--   (status, order_id) covers the filter AND the min() in one index scan.
CREATE INDEX idx_orders_status_order_id
    ON blinkit.orders (status, order_id);

-- R21: NOT EXISTS subquery filters orders by rider_id + placed_at.
--   (rider_id, placed_at) lets the planner jump straight to a rider's
--   orders and then cut by the placed_at range.
CREATE INDEX idx_orders_rider_placed
    ON blinkit.orders (rider_id, placed_at);

-- -----------------------------------------------------------------
-- Order items: the second workhorse table. product_id is currently the
-- SECOND column of order_items_pkey (order_id, product_id), so searching
-- by product_id alone can't use the primary key. This index fixes R12,
-- R13, R18 and R19 (the correlated R19 subquery is 1,905 ms in the baseline).
-- -----------------------------------------------------------------

-- R12 / R13 / R18 / R19: equality on product_id
--   The correlated R19 subquery runs once per Fruits & Vegetables product
--   (125 products x 675,000 order lines = ~84 million rows) in the baseline.
--   With (product_id), the subquery becomes one index scan per product.
CREATE INDEX idx_order_items_product_id
    ON blinkit.order_items (product_id);

-- -----------------------------------------------------------------
-- Inventory movements: two indexes for R24 (order_items join + store + date)
-- and W05 (delete old rows).
-- -----------------------------------------------------------------

-- R24: store_id equality, movement_type equality, moved_at range.
--   (store_id, movement_type, moved_at) is a covering-ish index for the
--   filter; the GROUP BY product_id is then applied to the small result.
CREATE INDEX idx_movements_store_type_moved
    ON blinkit.inventory_movements (store_id, movement_type, moved_at);

-- W05: range on moved_at for the DELETE.
--   (moved_at) lets the planner delete the 60,165 old rows with an index
--   scan instead of a full table scan.
CREATE INDEX idx_movements_moved_at
    ON blinkit.inventory_movements (moved_at);

-- =====================================================================
-- END OF FILE
-- =====================================================================
