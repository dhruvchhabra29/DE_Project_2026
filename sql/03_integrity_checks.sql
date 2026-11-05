-- =====================================================================
-- Blinkit DBMS Project · Team T0033
-- sql/03_integrity_checks.sql : does the loaded data make sense ACROSS tables?
--
-- Run after 01_schema.sql and 02_load_data.sql:
--   psql -d blinkit_seed -f sql/03_integrity_checks.sql
--
-- Why a separate file? A CHECK constraint can only look at ONE row of ONE table.
-- Every rule below compares two tables (an order and its store, rider, customer,
-- items...), so the database can't enforce it by itself. We test it with a query.
--
-- Each check counts the rows that BREAK the rule:
--   0      = the data obeys the rule
--   > 0    = a data problem. We keep the rows (the brief says load all the data)
--            and explain the problem in docs/02_schema_design.md.
-- =====================================================================

SET search_path TO blinkit;

SELECT n, check_name, rows_breaking_rule,
       CASE WHEN rows_breaking_rule = 0 THEN 'PASS' ELSE 'DATA PROBLEM' END AS result
FROM (

    -- 1. Every ordered product is stocked by the store that served the order.
    --    (A store can't sell something it doesn't carry.)
    SELECT 1 AS n, 'Ordered product is stocked by the order''s store' AS check_name,
           count(*) AS rows_breaking_rule
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE NOT EXISTS (SELECT 1 FROM store_inventory si
                      WHERE si.store_id = o.store_id AND si.product_id = oi.product_id)

    UNION ALL
    -- 2. A rider only delivers orders of their own store.
    SELECT 2, 'Rider belongs to the order''s store',
           count(*)
    FROM orders o
    JOIN riders r ON r.rider_id = o.rider_id
    WHERE r.store_id <> o.store_id

    UNION ALL
    -- 3. A substitute is a product that the same store stocks.
    SELECT 3, 'Substitute is stocked by the order''s store',
           count(*)
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE oi.substitute_product_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM store_inventory si
                      WHERE si.store_id = o.store_id AND si.product_id = oi.substitute_product_id)

    UNION ALL
    -- 4. orders.subtotal = sum(quantity_delivered x unit_price) of its items.
    --    (subtotal is a DERIVED column; this proves it is consistent.)
    SELECT 4, 'Subtotal = sum of delivered qty x unit price',
           count(*)
    FROM orders o
    JOIN (SELECT order_id, sum(quantity_delivered * unit_price) AS items_total
          FROM order_items GROUP BY order_id) t ON t.order_id = o.order_id
    WHERE o.subtotal <> t.items_total

    UNION ALL
    -- 5. Shelf life is filled for perishable products and blank for non-perishable ones.
    SELECT 5, 'Shelf life given only for perishable products',
           count(*)
    FROM products p
    JOIN categories c ON c.category_id = p.category_id
    WHERE (c.is_perishable AND p.shelf_life_days IS NULL)
       OR (NOT c.is_perishable AND p.shelf_life_days IS NOT NULL)

    UNION ALL
    -- 6. The first 3 letters of store_code are the city (MUM-... is in Mumbai).
    SELECT 6, 'Store code prefix matches the store''s city',
           count(*)
    FROM dark_stores s
    JOIN cities ci ON ci.city_id = s.city_id
    WHERE left(s.store_code, 3) <> upper(left(ci.city_name, 3))

    UNION ALL
    -- 7. A store never sells above the MRP (selling above MRP is illegal in India).
    SELECT 7, 'Store selling price is not above MRP',
           count(*)
    FROM store_inventory si
    JOIN products p ON p.product_id = si.product_id
    WHERE si.selling_price > p.mrp

    UNION ALL
    -- 8. An order can't be placed before the customer's account was created.
    SELECT 8, 'Order placed after the customer account was created',
           count(*)
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.placed_at < c.created_at

    UNION ALL
    -- 9. A rider can't handle an order before the day they joined.
    --    (::date drops the time, because joined_on is a plain date)
    SELECT 9, 'Order handled on/after the rider''s joining date',
           count(*)
    FROM orders o
    JOIN riders r ON r.rider_id = o.rider_id
    WHERE o.placed_at::date < r.joined_on

    UNION ALL
    -- 10. A CANCELLED order delivered nothing, so quantity_delivered should be 0.
    --     (counts cancelled ORDERS that still show delivered items)
    SELECT 10, 'Cancelled order shows 0 delivered items',
           count(DISTINCT o.order_id)
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'CANCELLED' AND oi.quantity_delivered > 0

) checks
ORDER BY n;


-- ---------------------------------------------------------------------
-- Detail for the 3 data problems (a few example rows each)
-- ---------------------------------------------------------------------

-- 8: orders older than the customer's account
SELECT o.order_id, o.customer_id, o.placed_at, c.created_at AS customer_created_at
FROM orders o JOIN customers c ON c.customer_id = o.customer_id
WHERE o.placed_at < c.created_at
ORDER BY o.order_id LIMIT 5;

-- 9: orders older than the rider's joining date
SELECT o.order_id, o.rider_id, o.placed_at::date AS order_date, r.joined_on
FROM orders o JOIN riders r ON r.rider_id = o.rider_id
WHERE o.placed_at::date < r.joined_on
ORDER BY o.order_id LIMIT 5;

-- 10: how big the cancelled-order problem is
SELECT count(DISTINCT o.order_id)                           AS cancelled_orders_with_delivered_items,
       (SELECT count(*) FROM orders WHERE status = 'CANCELLED') AS all_cancelled_orders,
       count(*)                                             AS item_lines,
       sum(oi.quantity_delivered)                           AS units_shown_as_delivered,
       sum(oi.quantity_delivered * oi.unit_price)           AS rupees_counted_in_subtotal
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'CANCELLED' AND oi.quantity_delivered > 0;
