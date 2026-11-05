-- =====================================================================
-- Blinkit DBMS Project · Team T0033
-- sql/02_load_data.sql : loads the 10 CSV files into the blinkit schema
--
-- Run from the repository root (where the seed_data/ folder is), after 01_schema.sql:
--   psql -d blinkit_seed -v ON_ERROR_STOP=1 -f sql/02_load_data.sql
--
-- For the large dataset (Phase 5), change only the folder name seed_data/ -> large_data/.
--
-- Order matters: parent tables first, so every foreign key already has its target row.
-- FORMAT csv  : comma-separated, "quoted" values allowed
-- HEADER true : skip the first line (the column names)
-- An empty field in a CSV file is loaded as NULL.
-- =====================================================================

SET search_path TO blinkit;

-- 1-4: tables with no parent, or whose parents are loaded just above
\copy cities       FROM 'seed_data/cities.csv'       WITH (FORMAT csv, HEADER true)
\copy categories   FROM 'seed_data/categories.csv'   WITH (FORMAT csv, HEADER true)
\copy dark_stores  FROM 'seed_data/dark_stores.csv'  WITH (FORMAT csv, HEADER true)
\copy products     FROM 'seed_data/products.csv'     WITH (FORMAT csv, HEADER true)

-- 5-7: need cities / dark_stores / products to exist first
\copy customers        FROM 'seed_data/customers.csv'        WITH (FORMAT csv, HEADER true)
\copy riders           FROM 'seed_data/riders.csv'           WITH (FORMAT csv, HEADER true)
\copy store_inventory  FROM 'seed_data/store_inventory.csv'  WITH (FORMAT csv, HEADER true)

-- 8: orders needs customers, dark_stores and riders
\copy orders           FROM 'seed_data/orders.csv'           WITH (FORMAT csv, HEADER true)

-- Refresh the planner's statistics, so the query plans in Phase 3 are realistic
ANALYZE;

-- Row-count check: the "expected" column is the table in the README
SELECT 'cities'      AS table_name, count(*) AS loaded, 10   AS expected FROM cities
UNION ALL SELECT 'categories',  count(*), 12   FROM categories
UNION ALL SELECT 'dark_stores', count(*), 120  FROM dark_stores
UNION ALL SELECT 'products',    count(*), 1500 FROM products
UNION ALL SELECT 'customers',   count(*), 40000  FROM customers
UNION ALL SELECT 'riders',      count(*), 1800   FROM riders
UNION ALL SELECT 'store_inventory', count(*), 126000 FROM store_inventory
UNION ALL SELECT 'orders',      count(*), 150000 FROM orders;
