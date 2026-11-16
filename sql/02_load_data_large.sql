-- =====================================================================
-- Blinkit DBMS Project · Team T0033
-- sql/02_load_data.sql : loads the 10 CSV files into the blinkit schema
--
-- Run from the repository root (where the large_data/ folder is), after 01_schema.sql:
--   psql -d blinkit_seed -v ON_ERROR_STOP=1 -f sql/02_load_data.sql
--
-- For the large dataset (Phase 5), change only the folder name large_data/ -> large_data/.
--
-- Order matters: parent tables first, so every foreign key already has its target row.
-- FORMAT csv  : comma-separated, "quoted" values allowed
-- HEADER true : skip the first line (the column names)
-- An empty field in a CSV file is loaded as NULL.
-- =====================================================================

SET search_path TO blinkit;

-- 1-4: tables with no parent, or whose parents are loaded just above
\copy cities               FROM 'large_data/cities.csv'               WITH (FORMAT csv, HEADER true)
\copy categories           FROM 'large_data/categories.csv'           WITH (FORMAT csv, HEADER true)
\copy dark_stores          FROM 'large_data/dark_stores.csv'          WITH (FORMAT csv, HEADER true)
\copy products             FROM 'large_data/products.csv'             WITH (FORMAT csv, HEADER true)

-- 5-7: need cities / dark_stores / products to exist first
\copy customers            FROM 'large_data/customers.csv'            WITH (FORMAT csv, HEADER true)
\copy riders               FROM 'large_data/riders.csv'               WITH (FORMAT csv, HEADER true)
\copy store_inventory      FROM 'large_data/store_inventory.csv'      WITH (FORMAT csv, HEADER true)

-- 8: orders needs customers, dark_stores and riders
\copy orders               FROM 'large_data/orders.csv'               WITH (FORMAT csv, HEADER true)

-- 9-10: order_items needs orders + products; movements need store_inventory
\copy order_items          FROM 'large_data/order_items.csv'          WITH (FORMAT csv, HEADER true)
\copy inventory_movements  FROM 'large_data/inventory_movements.csv'  WITH (FORMAT csv, HEADER true)

-- Refresh the planner's statistics, so the query plans in Phase 3 are realistic
ANALYZE;
