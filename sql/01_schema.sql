-- =====================================================================
-- Blinkit DBMS Project · Team T0033
-- sql/01_schema.sql : creates every table, with keys and constraints only
--
-- Run on an empty database:
--   psql -d blinkit_seed -v ON_ERROR_STOP=1 -f sql/01_schema.sql
--
-- Rules we follow (README Phase 2):
--   * Every table lives in the schema "blinkit".
--   * Table and column names are exactly the CSV file names and headers.
--   * Only PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL and CHECK.
--     No other index yet. PostgreSQL makes an index automatically for each
--     PRIMARY KEY and UNIQUE constraint, and that is allowed.
--   * Every constraint below accepts 100% of the seed data.
--
-- Data-type choices used everywhere:
--   ids            INTEGER        whole numbers. order_id grows to 90,000,001 in W01, still far below the 2.1 billion limit
--   money          NUMERIC(10,2)  exact decimals (no float rounding errors on rupees)
--   date + time    TIMESTAMPTZ    the CSVs carry a time zone (+05:30), so we keep it
--   date only      DATE
--   yes / no       BOOLEAN        the CSVs use t / f
--   codes, phones  VARCHAR(n)     text with a format CHECK. Phones are text: no maths, and they can start with 0 or +
--
-- ON DELETE rules used everywhere:
--   RESTRICT  for history (you cannot delete a customer, store, product or rider that is used by an order)
--   CASCADE   only for "part-of" rows (an order's items die with the order, a store's stock rows die with the store)
-- =====================================================================

DROP SCHEMA IF EXISTS blinkit CASCADE;   -- start clean, so this file can be re-run any time
CREATE SCHEMA blinkit;
SET search_path TO blinkit;

-- The queries compare TIMESTAMPTZ columns with plain dates such as '2026-06-01'.
-- PostgreSQL reads such a date in the session's time zone, so we pin this database
-- to Indian time. "June 2026" then means June in IST on every teammate's laptop.
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'Asia/Kolkata');
END $$;
SET timezone TO 'Asia/Kolkata';


-- ---------------------------------------------------------------------
-- 1. cities: one row per city (10 rows)
-- ---------------------------------------------------------------------
CREATE TABLE cities (
    city_id    INTEGER      PRIMARY KEY,                 -- 1..10, unique id of the city
    city_name  VARCHAR(50)  NOT NULL UNIQUE,             -- "Bengaluru": two cities can't share a name
    state      VARCHAR(50)  NOT NULL                     -- "Karnataka": many cities can share a state
);


-- ---------------------------------------------------------------------
-- 2. categories: product categories such as Dairy, Snacks (12 rows)
-- ---------------------------------------------------------------------
CREATE TABLE categories (
    category_id    INTEGER      PRIMARY KEY,             -- 1..12
    category_name  VARCHAR(50)  NOT NULL UNIQUE,         -- the queries look up categories by name (R02, R19)
    is_perishable  BOOLEAN      NOT NULL                 -- t = goes bad quickly (Dairy, Bakery...)
);


-- ---------------------------------------------------------------------
-- 3. dark_stores: the small warehouses that serve orders (120 rows)
-- ---------------------------------------------------------------------
CREATE TABLE dark_stores (
    store_id          INTEGER       PRIMARY KEY,
    store_code        VARCHAR(10)   NOT NULL UNIQUE,     -- e.g. MUM-AND-11: a second, human-readable key
    city_id           INTEGER       NOT NULL
                      REFERENCES cities (city_id) ON DELETE RESTRICT,   -- can't delete a city that still has stores
    latitude          NUMERIC(9,6)  NOT NULL,            -- 6 decimals in the CSV (about 10 cm accuracy)
    longitude         NUMERIC(9,6)  NOT NULL,
    opened_on         DATE          NOT NULL,
    is_active         BOOLEAN       NOT NULL DEFAULT TRUE,   -- 2 stores (51, 74) are closed
    max_daily_orders  INTEGER       NOT NULL,            -- capacity: 1500 / 2000 / 2500 / 3000

    -- CITY-AREA-NUMBER, e.g. MUM-AND-11 (3 capital letters, dash, 3 capital letters, dash, 2 digits)
    CONSTRAINT chk_store_code_format   CHECK (store_code ~ '^[A-Z]{3}-[A-Z]{3}-[0-9]{2}$'),
    -- every store is in India: latitude about 6..37 N, longitude about 68..98 E
    CONSTRAINT chk_store_latitude      CHECK (latitude  BETWEEN 6 AND 37),
    CONSTRAINT chk_store_longitude     CHECK (longitude BETWEEN 68 AND 98),
    -- a store must be able to take at least one order a day
    CONSTRAINT chk_store_capacity      CHECK (max_daily_orders > 0)
);


-- ---------------------------------------------------------------------
-- 4. products: the catalogue (1,500 rows)
-- ---------------------------------------------------------------------
CREATE TABLE products (
    product_id       INTEGER        PRIMARY KEY,
    sku              VARCHAR(10)    NOT NULL UNIQUE,     -- barcode id scanned in the warehouse (R23)
    product_name     VARCHAR(100)   NOT NULL,            -- NOT unique: the same name appears ~21 times with different SKUs
    brand            VARCHAR(50)    NOT NULL,
    category_id      INTEGER        NOT NULL
                     REFERENCES categories (category_id) ON DELETE RESTRICT,  -- can't delete a category that has products
    pack_size        VARCHAR(20)    NOT NULL,            -- free text such as "1 kg", "4 x 100 g", "12 pcs"
    mrp              NUMERIC(10,2)  NOT NULL,            -- maximum retail price in rupees
    shelf_life_days  SMALLINT       NULL,                -- blank (NULL) for non-perishables such as detergent
    is_active        BOOLEAN        NOT NULL DEFAULT TRUE,   -- 37 products are delisted

    -- SKU = "BK" + 8 digits, e.g. BK10007919
    CONSTRAINT chk_product_sku_format  CHECK (sku ~ '^BK[0-9]{8}$'),
    -- a price must be positive
    CONSTRAINT chk_product_mrp         CHECK (mrp > 0),
    -- if a shelf life is given, it must be at least 1 day (NULL is allowed and passes)
    CONSTRAINT chk_product_shelf_life  CHECK (shelf_life_days > 0)
);


-- ---------------------------------------------------------------------
-- 5. customers: people who order (40,000 rows)
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id  INTEGER       PRIMARY KEY,
    full_name    VARCHAR(100)  NOT NULL,                 -- NOT unique: many people share a name
    phone        VARCHAR(10)   NOT NULL UNIQUE,          -- login id: one account per phone number
    email        VARCHAR(100)  NULL UNIQUE,              -- optional (18,023 blank). UNIQUE still allows many NULLs
    city_id      INTEGER       NOT NULL
                 REFERENCES cities (city_id) ON DELETE RESTRICT,
    created_at   TIMESTAMPTZ   NOT NULL,                 -- when the account was created

    -- Indian mobile number: 10 digits, first digit 6-9
    CONSTRAINT chk_customer_phone_format  CHECK (phone ~ '^[6-9][0-9]{9}$'),
    -- simple e-mail shape: something@something.domain
    CONSTRAINT chk_customer_email_format  CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$'),
    -- store e-mails in lower case, so "A@x.com" and "a@x.com" can't both exist and dodge UNIQUE
    CONSTRAINT chk_customer_email_lower   CHECK (email = lower(email))
);


-- ---------------------------------------------------------------------
-- 6. riders: delivery riders, each attached to one store (1,800 rows, 15 per store)
-- ---------------------------------------------------------------------
CREATE TABLE riders (
    rider_id   INTEGER       PRIMARY KEY,
    full_name  VARCHAR(100)  NOT NULL,
    phone      VARCHAR(10)   NOT NULL UNIQUE,
    store_id   INTEGER       NOT NULL
               REFERENCES dark_stores (store_id) ON DELETE RESTRICT,   -- riders keep their history; mark them EXITED instead
    joined_on  DATE          NOT NULL,
    status     VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE',

    CONSTRAINT chk_rider_phone_format  CHECK (phone ~ '^[6-9][0-9]{9}$'),
    -- the only 3 values found in the data
    CONSTRAINT chk_rider_status        CHECK (status IN ('ACTIVE', 'ON_LEAVE', 'EXITED'))
);


-- ---------------------------------------------------------------------
-- 7. store_inventory: stock and price of ONE product in ONE store (126,000 rows)
--    Each store stocks 1,050 of the 1,500 products.
-- ---------------------------------------------------------------------
CREATE TABLE store_inventory (
    store_id          INTEGER        NOT NULL
                      REFERENCES dark_stores (store_id) ON DELETE CASCADE,  -- a stock row is part of its store
    product_id        INTEGER        NOT NULL
                      REFERENCES products (product_id) ON DELETE CASCADE,   -- ...and part of its product
    quantity_on_hand  INTEGER        NOT NULL,           -- units on the shelf right now
    reorder_level     INTEGER        NOT NULL,           -- when stock falls to this, reorder (R09, W04)
    selling_price     NUMERIC(10,2)  NOT NULL,           -- this store's price (can be below MRP)
    updated_at        TIMESTAMPTZ    NOT NULL,

    -- COMPOSITE primary key: neither column is unique alone,
    -- but each (store, product) pair appears exactly once
    PRIMARY KEY (store_id, product_id),

    -- stock can't go below zero (W02 uses greatest(0, ...) for the same reason)
    CONSTRAINT chk_inventory_qty_nonneg      CHECK (quantity_on_hand >= 0),
    CONSTRAINT chk_inventory_reorder_nonneg  CHECK (reorder_level >= 0),
    CONSTRAINT chk_inventory_price_positive  CHECK (selling_price > 0)
);


-- ---------------------------------------------------------------------
-- 8. orders: one row per customer order (150,000 rows, 1 Jan 2025 - 30 Jun 2026)
--
-- Life of an order:   PLACED -> PACKING -> OUT_FOR_DELIVERY -> DELIVERED
--                     (or CANCELLED at any point before pickup)
-- The time columns fill in as the order moves forward, so blanks are expected:
--   status             rider_id  packed_at  picked_up_at  delivered_at
--   PLACED             -         -          -             -
--   PACKING            -         yes        -             -
--   OUT_FOR_DELIVERY   yes       yes        yes           -
--   DELIVERED          yes       yes        yes           yes
--   CANCELLED          -         maybe      -             -      (cancelled before or after packing)
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id          INTEGER        PRIMARY KEY,
    customer_id       INTEGER        NOT NULL
                      REFERENCES customers (customer_id) ON DELETE RESTRICT,  -- keep order history: can't delete a customer with orders
    store_id          INTEGER        NOT NULL
                      REFERENCES dark_stores (store_id) ON DELETE RESTRICT,
    rider_id          INTEGER        NULL                                       -- blank until a rider is assigned
                      REFERENCES riders (rider_id) ON DELETE RESTRICT,         -- RESTRICT, not SET NULL: a delivered order must keep its rider
    placed_at         TIMESTAMPTZ    NOT NULL,
    packed_at         TIMESTAMPTZ    NULL,
    picked_up_at      TIMESTAMPTZ    NULL,
    delivered_at      TIMESTAMPTZ    NULL,
    promised_minutes  SMALLINT       NOT NULL DEFAULT 10,   -- the 10-minute promise. W01 does not send it, so DEFAULT fills it in
    subtotal          NUMERIC(10,2)  NOT NULL,              -- = sum(quantity_delivered x unit_price) of the order's items
    delivery_fee      NUMERIC(10,2)  NOT NULL DEFAULT 0,
    handling_fee      NUMERIC(10,2)  NOT NULL DEFAULT 0,
    small_cart_fee    NUMERIC(10,2)  NOT NULL DEFAULT 0,    -- always 0 in the seed data (see the design doc)
    total_amount      NUMERIC(10,2)  NOT NULL,              -- what the customer pays
    payment_method    VARCHAR(10)    NOT NULL,
    status            VARCHAR(20)    NOT NULL DEFAULT 'PLACED',

    -- allowed values (all found in the data)
    CONSTRAINT chk_order_payment_method  CHECK (payment_method IN ('UPI', 'CARD', 'COD', 'WALLET')),
    CONSTRAINT chk_order_status          CHECK (status IN ('PLACED', 'PACKING', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT chk_order_promised        CHECK (promised_minutes > 0),

    -- money can't be negative
    CONSTRAINT chk_order_money_nonneg    CHECK (subtotal >= 0 AND delivery_fee >= 0 AND handling_fee >= 0 AND small_cart_fee >= 0),
    -- how the bill is built: total = subtotal + all fees (true for all 150,000 rows)
    CONSTRAINT chk_order_total           CHECK (total_amount = subtotal + delivery_fee + handling_fee + small_cart_fee),
    -- fee rules found in the data (update these if Blinkit changes its pricing):
    --   delivery fee Rs 25 when the subtotal is below Rs 199, otherwise free
    CONSTRAINT chk_order_delivery_fee    CHECK (delivery_fee = CASE WHEN subtotal < 199 THEN 25 ELSE 0 END),
    --   handling fee Rs 6 when the subtotal is below Rs 500, otherwise Rs 2
    CONSTRAINT chk_order_handling_fee    CHECK (handling_fee = CASE WHEN subtotal < 500 THEN 6 ELSE 2 END),

    -- time must move forward: placed <= packed <= picked up <= delivered
    -- (a check on a NULL column passes, so orders that aren't packed yet are fine)
    CONSTRAINT chk_order_packed_after_placed      CHECK (packed_at    >= placed_at),
    CONSTRAINT chk_order_pickup_after_packed      CHECK (picked_up_at >= packed_at),
    CONSTRAINT chk_order_delivered_after_pickup   CHECK (delivered_at >= picked_up_at),

    -- each status must have exactly the right columns filled in (the table above)
    CONSTRAINT chk_order_status_timeline CHECK (
           (status = 'PLACED'           AND rider_id IS NULL     AND packed_at IS NULL     AND picked_up_at IS NULL     AND delivered_at IS NULL)
        OR (status = 'PACKING'          AND rider_id IS NULL                               AND picked_up_at IS NULL     AND delivered_at IS NULL)
        OR (status = 'OUT_FOR_DELIVERY' AND rider_id IS NOT NULL AND packed_at IS NOT NULL AND picked_up_at IS NOT NULL AND delivered_at IS NULL)
        OR (status = 'DELIVERED'        AND rider_id IS NOT NULL AND packed_at IS NOT NULL AND picked_up_at IS NOT NULL AND delivered_at IS NOT NULL)
        OR (status = 'CANCELLED'        AND rider_id IS NULL                               AND picked_up_at IS NULL     AND delivered_at IS NULL)
    )
    -- PACKING doesn't force packed_at: packing may have started but not finished.
    -- W03 handles exactly that case with coalesce(packed_at, ...).
);
