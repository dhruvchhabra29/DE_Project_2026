# Phase 2: Schema Design

**Team T0033** · Blinkit 10-minute grocery delivery database · PostgreSQL 17.10

We rebuilt the database **only from the 10 CSV exports**. For every column, we studied the data (blank values, distinct values, min/max, formats) and tested each rule against all rows before turning it into a constraint.

| File | What it does |
|---|---|
| [`sql/01_schema.sql`](../sql/01_schema.sql) | Creates schema `blinkit` and the 10 tables, with PK, FK, UNIQUE, NOT NULL and CHECK only |
| [`sql/02_load_data.sql`](../sql/02_load_data.sql) | Loads the 10 CSVs in foreign-key order, runs `ANALYZE`, prints a row-count check |
| [`sql/03_integrity_checks.sql`](../sql/03_integrity_checks.sql) | 10 cross-table checks (rules a CHECK constraint can't express) |

**How to rebuild from scratch** (from the repo root, after `unzip seed_data.zip`):
```bash
createdb blinkit_seed
psql -d blinkit_seed -v ON_ERROR_STOP=1 -f sql/01_schema.sql
psql -d blinkit_seed -v ON_ERROR_STOP=1 -f sql/02_load_data.sql
psql -d blinkit_seed -f sql/03_integrity_checks.sql
```

**Totals:** 10 tables · 10 primary keys · 13 foreign keys · 7 UNIQUE · **34 CHECK constraints** · 17 indexes (all automatic, from PK/UNIQUE).

---

## 1. Data dictionary

### How we chose data types

| Kind of value | Type | Why |
|---|---|---|
| ids | `INTEGER` | Whole numbers. The biggest id after W01 is 90,000,001, far below INTEGER's 2.1 billion limit, and 4 bytes is half the size of BIGINT. |
| money | `NUMERIC(10,2)` | **Exact** decimals. FLOAT would store ₹0.10 as 0.1000000000000000055…, and sums of money would drift. |
| date + time | `TIMESTAMPTZ` | The CSVs include a time zone (`+05:30`). TIMESTAMPTZ keeps the exact moment. The database is pinned to `Asia/Kolkata`. |
| date only | `DATE` | `opened_on` and `joined_on` have no time part. |
| yes/no | `BOOLEAN` | The CSVs use `t`/`f`. One byte, and queries can say `WHERE is_active`. |
| small counts | `SMALLINT` | `shelf_life_days`, `promised_minutes` and item quantities are small (max 180, 10 and 3). |
| codes, phones, names | `VARCHAR(n)` | Text with a sensible maximum length. **Phones are text, not numbers**: you never do maths on them, and leading `0`/`+` must survive. |
| latitude/longitude | `NUMERIC(9,6)` | The CSV has exactly 6 decimals (about 10 cm). NUMERIC keeps them exactly. |

**Key:** PK = primary key · FK = foreign key · NN = NOT NULL · UQ = UNIQUE · CK = CHECK

### 1.1 `cities` (10 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| city_id | INTEGER | **PK** | Identifies the city. Referenced by stores and customers. |
| city_name | VARCHAR(50) | NN, **UQ** | Two cities can't share a name. A natural candidate key. |
| state | VARCHAR(50) | NN | Many cities can be in one state (Mumbai and Pune are both in Maharashtra), so it is not unique. |

### 1.2 `categories` (12 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| category_id | INTEGER | **PK** | Identifies the category. |
| category_name | VARCHAR(50) | NN, **UQ** | Queries look categories up by name (`'Dairy'` in R02, `'Fruits & Vegetables'` in R19), so the name must be unique. |
| is_perishable | BOOLEAN | NN | `t` = goes bad quickly (Dairy, Fruits & Vegetables, Bakery, Frozen, Meat & Eggs). |

### 1.3 `dark_stores` (120 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| store_id | INTEGER | **PK** | Identifies the store. |
| store_code | VARCHAR(10) | NN, **UQ**, CK `chk_store_code_format` `^[A-Z]{3}-[A-Z]{3}-[0-9]{2}$` | Human-readable second key, e.g. `MUM-AND-11` = city-area-number. All 120 codes follow this format. |
| city_id | INTEGER | NN, **FK** → cities ON DELETE RESTRICT | Every store is in a city. You can't delete a city that still has stores. |
| latitude | NUMERIC(9,6) | NN, CK `chk_store_latitude` 6–37 | India lies between about 6°N and 37°N. Catches swapped or garbage coordinates. Used by R01. |
| longitude | NUMERIC(9,6) | NN, CK `chk_store_longitude` 68–98 | India lies between about 68°E and 98°E. |
| opened_on | DATE | NN | Every store has an opening date. |
| is_active | BOOLEAN | NN, DEFAULT TRUE | 2 stores (51, 74) are closed. R01 only assigns active stores. |
| max_daily_orders | INTEGER | NN, CK `chk_store_capacity` > 0 | Capacity (1,500 / 2,000 / 2,500 / 3,000). Zero or negative makes no sense. |

### 1.4 `products` (1,500 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| product_id | INTEGER | **PK** | Identifies the product. |
| sku | VARCHAR(10) | NN, **UQ**, CK `chk_product_sku_format` `^BK[0-9]{8}$` | Barcode id scanned in the warehouse (R23). Unique for every product. |
| product_name | VARCHAR(100) | NN | **Not unique**: only 70 names for 1,500 products (see data problems). |
| brand | VARCHAR(50) | NN | Always present (24 brands). |
| category_id | INTEGER | NN, **FK** → categories ON DELETE RESTRICT | Every product is in a category. You can't delete a category that has products. |
| pack_size | VARCHAR(20) | NN | Free text such as `1 kg`, `4 x 100 g`, `12 pcs`, so it stays text. |
| mrp | NUMERIC(10,2) | NN, CK `chk_product_mrp` > 0 | Maximum retail price. Must be positive. |
| shelf_life_days | SMALLINT | **NULL allowed**, CK `chk_product_shelf_life` > 0 | **Blank for exactly the 875 non-perishable products**. A detergent doesn't expire in days. If given, it must be at least 1. |
| is_active | BOOLEAN | NN, DEFAULT TRUE | 37 products are delisted. R13 lists only active products. |

### 1.5 `customers` (40,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| customer_id | INTEGER | **PK** | Identifies the customer. |
| full_name | VARCHAR(100) | NN | Not unique: only 500 distinct names among 40,000 people. |
| phone | VARCHAR(10) | NN, **UQ**, CK `chk_customer_phone_format` `^[6-9][0-9]{9}$` | The login id, so it's one account per phone. An Indian mobile number is 10 digits starting with 6–9. |
| email | VARCHAR(100) | **NULL allowed**, **UQ**, CK `chk_customer_email_format`, CK `chk_customer_email_lower` | **Optional** (18,023 blank), because sign-up only needs a phone. UNIQUE still allows many NULLs. We require lower case so `A@x.com` and `a@x.com` can't both exist and get around UNIQUE. |
| city_id | INTEGER | NN, **FK** → cities ON DELETE RESTRICT | Home city. R25 filters on it. |
| created_at | TIMESTAMPTZ | NN | When the account was created (see data problem D1). |

### 1.6 `riders` (1,800 rows, 15 per store)
| Column | Type | Constraints | Why |
|---|---|---|---|
| rider_id | INTEGER | **PK** | Identifies the rider. |
| full_name | VARCHAR(100) | NN | Not unique. |
| phone | VARCHAR(10) | NN, **UQ**, CK `chk_rider_phone_format` | Each rider has their own number. |
| store_id | INTEGER | NN, **FK** → dark_stores ON DELETE RESTRICT | Every rider works for one store. RESTRICT keeps delivery history safe. |
| joined_on | DATE | NN | Joining date (see data problem D2). |
| status | VARCHAR(10) | NN, DEFAULT 'ACTIVE', CK `chk_rider_status` IN (ACTIVE, ON_LEAVE, EXITED) | The only 3 values in the data. A rider who leaves becomes EXITED instead of being deleted. |

### 1.7 `store_inventory` (126,000 rows: each store stocks 1,050 of the 1,500 products)
| Column | Type | Constraints | Why |
|---|---|---|---|
| store_id | INTEGER | NN, **PK part 1**, **FK** → dark_stores ON DELETE CASCADE | A stock row is *part of* its store. |
| product_id | INTEGER | NN, **PK part 2**, **FK** → products ON DELETE CASCADE | …and *part of* its product. |
| quantity_on_hand | INTEGER | NN, CK `chk_inventory_qty_nonneg` ≥ 0 | Units on the shelf. Stock can't be negative (W02 uses `greatest(0, …)` for the same reason). 7,200 rows are 0, meaning out of stock. |
| reorder_level | INTEGER | NN, CK `chk_inventory_reorder_nonneg` ≥ 0 | When stock falls to this level, reorder (R09, W04). Values 5–15. |
| selling_price | NUMERIC(10,2) | NN, CK `chk_inventory_price_positive` > 0 | This store's own price. Never above MRP (integrity check 7). |
| updated_at | TIMESTAMPTZ | NN | Last change to the row. |

**Primary key `(store_id, product_id)`:** neither column is unique alone, but each pair appears exactly once.

### 1.8 `orders` (150,000 rows, 1 Jan 2025 – 30 Jun 2026)
| Column | Type | Constraints | Why |
|---|---|---|---|
| order_id | INTEGER | **PK** | Identifies the order. |
| customer_id | INTEGER | NN, **FK** → customers ON DELETE RESTRICT | Order history must survive, so a customer with orders can't be deleted. |
| store_id | INTEGER | NN, **FK** → dark_stores ON DELETE RESTRICT | The store that served the order. |
| rider_id | INTEGER | **NULL allowed**, **FK** → riders ON DELETE RESTRICT | **Blank until a rider is assigned**: PLACED, PACKING and CANCELLED orders (5,822). RESTRICT rather than SET NULL, because a DELIVERED order must keep its rider. |
| placed_at | TIMESTAMPTZ | NN | Always known. |
| packed_at | TIMESTAMPTZ | NULL allowed | Blank if not packed yet (PLACED) or cancelled before packing (2,885). |
| picked_up_at | TIMESTAMPTZ | NULL allowed | Blank until a rider picks the order up (5,822, the same rows as a blank rider_id). |
| delivered_at | TIMESTAMPTZ | NULL allowed | Blank for every order that isn't DELIVERED (5,857). |
| promised_minutes | SMALLINT | NN, DEFAULT 10, CK > 0 | The 10-minute promise. **W01 doesn't send this column**, so the DEFAULT fills it in. |
| subtotal | NUMERIC(10,2) | NN, CK ≥ 0 | Σ(quantity_delivered × unit_price) of the items. A **derived** column (see §4). |
| delivery_fee | NUMERIC(10,2) | NN, DEFAULT 0, CK ≥ 0, CK `chk_order_delivery_fee` | **₹25 when subtotal < ₹199, else ₹0.** This holds for all 150,000 rows. |
| handling_fee | NUMERIC(10,2) | NN, DEFAULT 0, CK ≥ 0, CK `chk_order_handling_fee` | **₹6 when subtotal < ₹500, else ₹2.** This holds for all 150,000 rows. |
| small_cart_fee | NUMERIC(10,2) | NN, DEFAULT 0, CK ≥ 0 | Always ₹0 in the seed data (data problem D5). |
| total_amount | NUMERIC(10,2) | NN, CK `chk_order_total` | **total = subtotal + delivery + handling + small-cart fee.** This holds for all 150,000 rows. |
| payment_method | VARCHAR(10) | NN, CK IN (UPI, CARD, COD, WALLET) | The only 4 values in the data. |
| status | VARCHAR(20) | NN, DEFAULT 'PLACED', CK IN (PLACED, PACKING, OUT_FOR_DELIVERY, DELIVERED, CANCELLED) | The order's life cycle. |

**Time-order CHECKs:** `chk_order_packed_after_placed`, `chk_order_pickup_after_packed` and `chk_order_delivered_after_pickup` make sure placed ≤ packed ≤ picked up ≤ delivered. A CHECK on a NULL value passes, so unfinished orders are fine.

**Status CHECK `chk_order_status_timeline`:** each status must have exactly the right columns filled in.

| status | rider_id | packed_at | picked_up_at | delivered_at | rows |
|---|:-:|:-:|:-:|:-:|--:|
| PLACED | – | – | – | – | 35 |
| PACKING | – | any | – | – | 35 |
| OUT_FOR_DELIVERY | ✔ | ✔ | ✔ | – | 35 |
| DELIVERED | ✔ | ✔ | ✔ | ✔ | 144,143 |
| CANCELLED | – | any | – | – | 5,752 (2,902 packed, 2,850 not) |

PACKING allows a blank `packed_at` (packing may have started but not finished). W03 handles exactly that case with `coalesce(packed_at, …)`.

### 1.9 `order_items` (675,000 rows, 2–7 lines per order)
| Column | Type | Constraints | Why |
|---|---|---|---|
| order_id | INTEGER | NN, **PK part 1**, **FK** → orders ON DELETE CASCADE | A line is *part of* its order: delete the order and its lines go too. |
| product_id | INTEGER | NN, **PK part 2**, **FK** → products ON DELETE RESTRICT | A product that has been sold can't be deleted. |
| quantity_ordered | SMALLINT | NN, CK `chk_item_qty_ordered` > 0 | 1–3 in the data. Ordering 0 makes no sense. |
| quantity_delivered | SMALLINT | NN, CK `chk_item_qty_delivered` BETWEEN 0 AND quantity_ordered | Less than ordered when the item ran out (a "short" delivery). Never more than ordered. |
| unit_price | NUMERIC(10,2) | NN, CK `chk_item_price_positive` > 0 | The price **at the time of the order**. Kept as a copy because store prices change later. |
| substitute_product_id | INTEGER | **NULL allowed**, **FK** → products ON DELETE RESTRICT, CK `chk_item_substitute_differs`, CK `chk_item_substitute_only_if_short` | **Blank on 660,000 of 675,000 lines**, because no replacement was needed. If given, it must be a *different* product, and only on a line that was delivered short. |

**Primary key `(order_id, product_id)`:** a product appears at most once per order. A bigger quantity goes in `quantity_ordered`.

### 1.10 `inventory_movements` (90,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| movement_id | INTEGER | **PK** | Identifies the movement. |
| store_id | INTEGER | NN, **FK part 1** → store_inventory | See the composite FK below. |
| product_id | INTEGER | NN, **FK part 2** → store_inventory | |
| movement_type | VARCHAR(12) | NN, CK `chk_movement_type` IN (RESTOCK, DAMAGE, EXPIRY, ADJUSTMENT) | The only 4 values in the data. |
| quantity | INTEGER | NN, CK `chk_movement_nonzero` ≠ 0, CK `chk_movement_sign` | **Signed**: + units in, − units out. The sign must match the type: RESTOCK > 0, DAMAGE/EXPIRY < 0, ADJUSTMENT either way (a stock-count correction). |
| moved_at | TIMESTAMPTZ | NN | When the stock changed. |

**Composite FK `fk_movement_inventory (store_id, product_id) → store_inventory`, ON DELETE RESTRICT.** A movement changes **one stock row**, so it points to that exact row, not to stores and products separately. That also guarantees a store never records movements for a product it doesn't stock. RESTRICT, because stock history is audit data.

### CHECK constraints: full list (34)
| # | Table | Constraint | Rule |
|--:|---|---|---|
| 1 | dark_stores | chk_store_code_format | code looks like `ABC-DEF-12` |
| 2 | dark_stores | chk_store_latitude | 6 ≤ latitude ≤ 37 |
| 3 | dark_stores | chk_store_longitude | 68 ≤ longitude ≤ 98 |
| 4 | dark_stores | chk_store_capacity | max_daily_orders > 0 |
| 5 | products | chk_product_sku_format | `BK` + 8 digits |
| 6 | products | chk_product_mrp | mrp > 0 |
| 7 | products | chk_product_shelf_life | shelf life > 0 (or blank) |
| 8 | customers | chk_customer_phone_format | 10 digits, starts 6–9 |
| 9 | customers | chk_customer_email_format | `x@y.zz` shape |
| 10 | customers | chk_customer_email_lower | e-mail is lower case |
| 11 | riders | chk_rider_phone_format | 10 digits, starts 6–9 |
| 12 | riders | chk_rider_status | ACTIVE / ON_LEAVE / EXITED |
| 13 | store_inventory | chk_inventory_qty_nonneg | stock ≥ 0 |
| 14 | store_inventory | chk_inventory_reorder_nonneg | reorder level ≥ 0 |
| 15 | store_inventory | chk_inventory_price_positive | selling price > 0 |
| 16 | orders | chk_order_payment_method | UPI / CARD / COD / WALLET |
| 17 | orders | chk_order_status | 5 allowed statuses |
| 18 | orders | chk_order_promised | promised minutes > 0 |
| 19 | orders | chk_order_money_nonneg | no negative money |
| 20 | orders | chk_order_total | total = subtotal + all fees |
| 21 | orders | chk_order_delivery_fee | ₹25 below ₹199, else 0 |
| 22 | orders | chk_order_handling_fee | ₹6 below ₹500, else ₹2 |
| 23 | orders | chk_order_packed_after_placed | packed ≥ placed |
| 24 | orders | chk_order_pickup_after_packed | picked up ≥ packed |
| 25 | orders | chk_order_delivered_after_pickup | delivered ≥ picked up |
| 26 | orders | chk_order_status_timeline | each status fills the right columns |
| 27 | order_items | chk_item_qty_ordered | ordered > 0 |
| 28 | order_items | chk_item_qty_delivered | 0 ≤ delivered ≤ ordered |
| 29 | order_items | chk_item_price_positive | unit price > 0 |
| 30 | order_items | chk_item_substitute_differs | substitute ≠ product |
| 31 | order_items | chk_item_substitute_only_if_short | substitute only on a short line |
| 32 | inventory_movements | chk_movement_type | 4 allowed types |
| 33 | inventory_movements | chk_movement_nonzero | quantity ≠ 0 |
| 34 | inventory_movements | chk_movement_sign | sign matches the type |

> The fee rules (21, 22) are business rules we found in the data. If Blinkit changes its prices, these two constraints must be updated in the same release.

---

## 2. Keys and relationships

### 2.1 Relationships and cardinalities
| Parent (one) | Child (many) | Cardinality | Foreign key | ON DELETE | Why this rule |
|---|---|---|---|---|---|
| cities | dark_stores | 1 : N | `dark_stores.city_id` | RESTRICT | A city with stores is still in use. |
| cities | customers | 1 : N | `customers.city_id` | RESTRICT | The same reason. |
| categories | products | 1 : N | `products.category_id` | RESTRICT | Products would lose their category. |
| dark_stores | riders | 1 : N (15 per store) | `riders.store_id` | RESTRICT | Riders carry delivery history. Mark them EXITED instead. |
| dark_stores ↔ products | store_inventory | **M : N** (a store stocks many products, a product is in many stores) | `store_inventory.store_id`, `.product_id` | **CASCADE** | A stock row has no meaning without its store or product, because it is *part of* both. |
| customers | orders | 1 : N | `orders.customer_id` | RESTRICT | Order history (finance, support) must never vanish. |
| dark_stores | orders | 1 : N | `orders.store_id` | RESTRICT | The same reason. |
| riders | orders | 1 : N, **optional** (an order has 0 or 1 rider) | `orders.rider_id` (NULL allowed) | RESTRICT | Not SET NULL: a DELIVERED order must keep its rider (enforced by `chk_order_status_timeline`). |
| orders ↔ products | order_items | **M : N** (an order has many products, a product is in many orders) | `order_items.order_id`, `.product_id` | order → **CASCADE**, product → RESTRICT | An item line is *part of* its order. A product that was sold must stay. |
| products | order_items (as substitute) | 1 : N, **optional** | `order_items.substitute_product_id` | RESTRICT | The same reason as product_id. |
| store_inventory | inventory_movements | 1 : N | **composite** `(store_id, product_id)` | RESTRICT | Stock history is audit data. |

**What happens in practice?** Deleting a store would cascade to its stock rows, but the store's orders, riders and movements all RESTRICT, so **PostgreSQL blocks the delete**. That's what we want: in a real business you close a store (`is_active = false`), you don't delete it. The only delete that really cascades is **an order → its order_items**.

**Note:** PostgreSQL does **not** create an index for a foreign-key column automatically. So `orders.customer_id`, `orders.store_id`, `order_items.product_id` and the others have **no index yet**. That's one reason many of the 30 queries will be slow in the Phase 3 baseline. We add indexes in Phase 4.

### 2.2 Candidate keys
| Table | Primary key | Other candidate keys (UNIQUE) |
|---|---|---|
| cities | city_id | city_name |
| categories | category_id | category_name |
| dark_stores | store_id | store_code |
| products | product_id | sku |
| customers | customer_id | phone, email (when given) |
| riders | rider_id | phone |
| store_inventory | **(store_id, product_id)** | none |
| orders | order_id | none |
| order_items | **(order_id, product_id)** | none |
| inventory_movements | movement_id | none |

### 2.3 Indexes that exist after Phase 2 (all automatic)
PostgreSQL builds one B-tree index for each PRIMARY KEY and UNIQUE constraint. **We created no other index**, so the Phase 3 baseline shows an untuned database.

| Table | Index | Columns | From | Size |
|---|---|---|---|--:|
| cities | cities_pkey | city_id | PK | 16 kB |
| cities | cities_city_name_key | city_name | UNIQUE | 16 kB |
| categories | categories_pkey | category_id | PK | 16 kB |
| categories | categories_category_name_key | category_name | UNIQUE | 16 kB |
| dark_stores | dark_stores_pkey | store_id | PK | 16 kB |
| dark_stores | dark_stores_store_code_key | store_code | UNIQUE | 16 kB |
| products | products_pkey | product_id | PK | 48 kB |
| products | products_sku_key | sku | UNIQUE | 64 kB |
| customers | customers_pkey | customer_id | PK | 896 kB |
| customers | customers_phone_key | phone | UNIQUE | 1,248 kB |
| customers | customers_email_key | email | UNIQUE | 1,440 kB |
| riders | riders_pkey | rider_id | PK | 56 kB |
| riders | riders_phone_key | phone | UNIQUE | 72 kB |
| store_inventory | store_inventory_pkey | (store_id, product_id) | PK | 2,792 kB |
| orders | orders_pkey | order_id | PK | 3,312 kB |
| order_items | order_items_pkey | (order_id, product_id) | PK | 15 MB |
| inventory_movements | inventory_movements_pkey | movement_id | PK | 1,984 kB |

What these already help: **R05** (cart check) and **R09** use `store_inventory_pkey` because `store_id` is its first column. **R23** (SKU lookup) uses `products_sku_key`. **R04** (one product in every store) can't use `store_inventory_pkey` well, because `product_id` is the *second* column of that index.

---

## 3. Functional dependencies and normal forms

**Quick reminder:**
- **FD** `X → Y` means "if you know X, you know Y".
- **1NF:** every cell holds one value, and there are no repeating groups.
- **2NF:** 1NF, and no column depends on only *part* of a composite key.
- **3NF:** 2NF, and no non-key column depends on another non-key column (no *transitive* dependency).
- **BCNF:** for every FD `X → Y`, X is a candidate key.

We wrote the FDs from the meaning of the data, then **tested each suspicious one with SQL on all rows** (the numbers below).

**1NF holds for every table.** Each cell is one value, and there are no lists or repeating columns. `pack_size` values such as `4 x 100 g` are a single label printed on the pack, not a list we query inside.

| Table | Functional dependencies | Normal form |
|---|---|---|
| cities | city_id → city_name, state · city_name → city_id, state | **BCNF**: both determinants are candidate keys. state → city does **not** hold (Maharashtra has Mumbai and Pune). |
| categories | category_id → category_name, is_perishable · category_name → category_id, is_perishable | **BCNF** |
| dark_stores | store_id → store_code, city_id, latitude, longitude, opened_on, is_active, max_daily_orders · store_code → store_id (and everything) | **BCNF**: every determinant is a candidate key. *Note:* the first 3 letters of `store_code` repeat the city (`MUM` = Mumbai). That's a small redundancy inside a label, kept because the code is a human-readable id. Integrity check 6 proves it's always consistent. |
| products | product_id → sku, product_name, brand, category_id, pack_size, mrp, shelf_life_days, is_active · sku → product_id (and everything) · **product_name → brand, category_id, pack_size, shelf_life_days** *(holds in the data: each of the 70 names has exactly 1 brand, 1 category, 1 pack size and 1 shelf life)* | **Not strictly 3NF**, because product_name is not a key but decides 4 other columns. See the explanation below the table. |
| customers | customer_id → full_name, phone, email, city_id, created_at · phone → customer_id · email → customer_id (when not NULL) | **BCNF** |
| riders | rider_id → full_name, phone, store_id, joined_on, status · phone → rider_id | **BCNF** |
| store_inventory | (store_id, product_id) → quantity_on_hand, reorder_level, selling_price, updated_at | **BCNF**. **2NF check:** no column depends on just one half of the key. Tested: every product has *different* reorder levels and prices in different stores (1,500 of 1,500), and every store has different values for different products (120 of 120). |
| orders | order_id → every column · **subtotal → delivery_fee, handling_fee** · **(subtotal, delivery_fee, handling_fee, small_cart_fee) → total_amount** · **rider_id → store_id** *(the rider's store, true for 144,178 of 144,178 orders with a rider)* | **Not strictly 3NF**: the fees and total depend on subtotal, and store_id depends on rider_id. All deliberate. See §4. |
| order_items | (order_id, product_id) → quantity_ordered, quantity_delivered, unit_price, substitute_product_id | **BCNF**. 2NF holds: quantities and substitute belong to this line, not to the order or product alone. unit_price is a historical copy (§4). |
| inventory_movements | movement_id → store_id, product_id, movement_type, quantity, moved_at | **BCNF** |

### 3.1 products: why we don't split the table
In the export, the **name already decides the brand, category, pack size and shelf life** ("Vim Detergent 1 kg" is always brand Vim, category Household, pack 1 kg). Only `sku`, `mrp` and `is_active` change between the about 21 rows sharing a name. The textbook 3NF fix would be:
```
product_master(product_name PK, brand, category_id, pack_size, shelf_life_days)
products(product_id PK, sku, product_name FK, mrp, is_active)
```
**We keep the single table**, because:
1. The 30 queries are fixed and read `p.category_id`, `p.brand` and `p.pack_size` from `products` (R02, R13, R19, R23). Splitting the table would break them.
2. In a real catalogue, two products *can* share a display name and differ in brand or pack. So "name → brand" is probably a coincidence of this export, not a true business rule. A true FD is a rule that must hold for all future data, not just today's rows.

We record it as a known redundancy (data problem D4).

---

## 4. Derived and redundant columns (and whether keeping them is justified)

| Column | Can be computed from | Proof in our data | Keep it? | Why |
|---|---|---|---|---|
| `orders.subtotal` | Σ(quantity_delivered × unit_price) of the order's items | Equal for **150,000 of 150,000** orders (integrity check 4) | ✅ Yes | Reports (R17, R20, R25) and the bill would otherwise have to add up 675,000 item lines every time. The value is fixed once the order is done. |
| `orders.delivery_fee`, `orders.handling_fee` | The fee rules applied to subtotal | `chk_order_delivery_fee` and `chk_order_handling_fee` pass on all rows | ✅ Yes | **History:** if Blinkit changes the ₹199 / ₹500 rules next year, old orders must still show the fee the customer actually paid. The CHECKs keep them consistent today. |
| `orders.total_amount` | subtotal + all fees | `chk_order_total` passes on all rows | ✅ Yes | The amount actually charged. Finance (R20, R25) sums it directly, and the CHECK means it can never drift. |
| `orders.store_id` | `riders.store_id` of the order's rider | Equal for **144,178 of 144,178** orders with a rider (integrity check 2) | ✅ Yes | PLACED, PACKING and CANCELLED orders have **no rider**, but still need a store. Every store query (R07, R08, R11, R14) filters on it. |
| `order_items.unit_price` | `store_inventory.selling_price` | Equal for **675,000 of 675,000** lines *today* | ✅ Yes | A **price snapshot**: store prices change every day, but an old bill must not change. Same reasoning as `subtotal`. |
| `store_inventory.quantity_on_hand` | Opening stock + Σ movements − Σ items sold | Only **888 of 126,000** rows equal "movements − delivered sales". The export has no opening stock, so it **can't** be recomputed | ✅ Yes | It's the live balance that checkout (R05) and the store screens (R02, R03, R09) need in under 5 ms. Recomputing it from 765,000 rows on every page view would be far too slow. W02 and W04 keep it up to date. |

**Summary:** each redundant column is kept on purpose, either for **speed** (no need to recompute from big tables) or for **history** (the value at the time of the order must not change). Where it can be checked inside one row, a **CHECK constraint** guarantees it stays correct (total, fees). Where it crosses tables, an **integrity check** proves it (subtotal, rider's store).

---

## 5. Load results

Built from an empty database: `01_schema.sql` → `02_load_data.sql`. **No errors. All rows load, and all constraints pass.** The whole rebuild takes about 7 seconds, and the database is 102 MB.

| # | Table | Rows loaded | Expected (README) | OK |
|--:|---|--:|--:|:-:|
| 1 | cities | 10 | 10 | ✅ |
| 2 | categories | 12 | 12 | ✅ |
| 3 | dark_stores | 120 | 120 | ✅ |
| 4 | products | 1,500 | 1,500 | ✅ |
| 5 | customers | 40,000 | 40,000 | ✅ |
| 6 | riders | 1,800 | 1,800 | ✅ |
| 7 | store_inventory | 126,000 | 126,000 | ✅ |
| 8 | orders | 150,000 | 150,000 | ✅ |
| 9 | order_items | 675,000 | 675,000 | ✅ |
| 10 | inventory_movements | 90,000 | 90,000 | ✅ |

**Load order** (parents before children, so every FK target already exists):
`cities → categories → dark_stores → products → customers → riders → store_inventory → orders → order_items → inventory_movements`

**Did any constraint fail while loading?** No. We profiled every column first (blank counts, distinct values, min/max, formats), then tested each rule with a query **before** writing it as a constraint. Rules that the data breaks only *across* tables can't be CHECK constraints, so they became integrity checks instead (§6), and the rows that break them are reported as data problems (§7).

**All 30 workload queries** (`queries/workload_30.sql`) run on this schema without errors.

---

## 6. Integrity-check results

From [`sql/03_integrity_checks.sql`](../sql/03_integrity_checks.sql). Each check counts the rows that **break** a rule.

| # | Rule (compares two tables) | Rows breaking it | Result |
|--:|---|--:|:-:|
| 1 | Every ordered product is stocked by the order's store | 0 | ✅ PASS |
| 2 | A rider only delivers orders of their own store | 0 | ✅ PASS |
| 3 | A substitute is a product the same store stocks | 0 | ✅ PASS |
| 4 | `subtotal` = Σ(quantity_delivered × unit_price) | 0 | ✅ PASS |
| 5 | Shelf life is given only for perishable products | 0 | ✅ PASS |
| 6 | Store-code prefix matches the store's city | 0 | ✅ PASS |
| 7 | Store selling price is not above MRP | 0 | ✅ PASS |
| 8 | Order placed after the customer account was created | 25,171 | ⚠️ data problem D1 |
| 9 | Order handled on or after the rider's joining date | 23,231 | ⚠️ data problem D2 |
| 10 | A cancelled order shows 0 delivered items | 5,752 | ⚠️ data problem D3 |

---

## 7. Data problems found

We **kept every row**. The brief says the schema must accept all the data, and deleting or "fixing" rows is not allowed. Each problem is explained here instead.

| # | Problem | Size | Likely cause | Effect on the 30 queries |
|---|---|---|---|---|
| **D1** | Orders placed **before the customer's account was created**. Example: order 5 on 1 Jan 2025, customer 1469 created on 11 Jun 2025. | 25,171 orders (17%), 10,263 customers | `created_at` was overwritten later (re-registration or a phone change), so it isn't the real sign-up date | None directly. No query uses `customers.created_at`. R16 builds cohorts from the **first order**, which is the right choice for this reason. |
| **D2** | Orders handled by a rider **before the rider joined**. Example: order 9 on 1 Jan 2025, rider 226 joined on 10 Mar 2026. | 23,231 orders, 652 riders | `joined_on` is probably the date of the rider's *latest* contract | None directly. Rider tenure analysis would be wrong. |
| **D3** | **Every cancelled order still shows delivered items**, and they're counted in `subtotal`/`total_amount`. Example: order 7 is CANCELLED, but its 3 lines show 2/2, 1/1 and 3/3 delivered. | All 5,752 cancelled orders · 25,419 lines · 50,567 units · ₹66,74,306 in subtotals | `quantity_delivered` is filled at packing time and never reset when the order is cancelled | **R19** (units sold), **R18** (dead stock) and **R14** (fill rate) don't filter on status, so cancelled orders count as sales. **R17** sums fees of cancelled orders too. R08, R11, R20 and R25 filter `status = 'DELIVERED'` and are unaffected. |
| **D4** | Only **70 product names for 1,500 products**. Each name appears about 21 times with a different SKU and MRP (e.g. "Vim Detergent 1 kg" ×21). | 1,500 products | Duplicate catalogue entries (the same item listed under many SKUs) | `product_name` can't be UNIQUE. **R03** (search "milk") returns several rows per name. **R19** lists the same name many times. |
| **D5** | `small_cart_fee` is **₹0 on every order**, but the brief says small carts pay extra. The small-cart charge actually appears as the ₹25 `delivery_fee` on orders below ₹199. | 150,000 orders (2,320 paid the ₹25) | The fee is booked in the wrong column | **R17** (small-cart fee per city per month) returns **0 for every row**. That's a correct answer to the query, but a misleading one for finance. |
| **D6** | `quantity_on_hand` **doesn't match** movements − sales. | 125,112 of 126,000 rows don't match | The export has no opening-stock figure, and stock is counted separately | We can't rebuild stock from history, so the column is the source of truth (see §4). |
| **D7** | The 2 inactive stores (51, 74) still have stock rows, but no orders or movements. | 2,100 stock rows | Stores were closed without clearing inventory | R04 and R09 could show stock at a closed store. R01 correctly skips them (`WHERE is_active`). |

### 7.1 NULLs that will matter in Phase 4
`order_items.substitute_product_id` is **NULL on 660,000 of 675,000 lines**. Query **R13** uses `product_id NOT IN (SELECT substitute_product_id …)`. In SQL, `x NOT IN (list that contains a NULL)` is never TRUE, because comparing with NULL gives "unknown". So **R13 always returns 0 rows**, which is exactly the category team's complaint in **P5**. We confirmed that R13 returns 0 rows on our schema. The fix (`NOT EXISTS`) comes in Phase 4.

---

## 8. ER diagram

See [`diagrams/er_diagram.png`](../diagrams/er_diagram.png) (added in a separate commit, with its Mermaid source).
