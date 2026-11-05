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
