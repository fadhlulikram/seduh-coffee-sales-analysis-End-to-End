/* @datacloud.settings
{
  "version": 1,
  "service": "BIG_QUERY",
  "connectionInfo": {
    "billingProjectId": "INHERIT"
  },
  "dialect": "GOOGLE_SQL"
}
*/

/* @datacloud.settings
{
  "version": 1,
  "service": "BIG_QUERY",
  "connectionInfo": {
    "billingProjectId": "INHERIT"
  },
  "dialect": "GOOGLE_SQL"
}
*/
CREATE OR REPLACE TABLE `talentiv.final.ENRICHED` AS
SELECT
  od.order_id,                                     -- PK
  od.order_date,
  od.customer_id,                                  -- FK ke customers
  od.product_id,                                   -- FK ke products
  od.quantity,
  od.unit_price,
  od.discount_pct,
  od.channel,
  od.payment_method,
  od.city,                                         -- kota pengiriman
  od.province,
  od.order_status,
  od.rating,
  od.review_text,

  prod.product_name,                               -- dari products
  prod.category,
  prod.unit_cost,

  cust.gender,                                     -- dari customers
  cust.age,
  cust.city AS customer_city,                      -- di-rename biar tidak bentrok dengan od.city
  cust.acquisition_channel,

  ROUND(od.unit_price * (1 - od.discount_pct)) AS net_unit_price,             -- harga setelah diskon
  ROUND(od.unit_price * (1 - od.discount_pct) * od.quantity) AS revenue,      -- harga bersih x jumlah
  prod.unit_cost * od.quantity AS cogs,                                       -- modal x jumlah
  ROUND(od.unit_price * (1 - od.discount_pct) * od.quantity)
    - prod.unit_cost * od.quantity AS profit,                                 -- revenue - cogs
  ROUND(od.unit_price * od.discount_pct * od.quantity) AS discount_idr,       -- total rupiah diskon
  od.order_status = 'Completed' AS is_completed,                              -- semua baris pasti TRUE
  DATE_TRUNC(od.order_date, MONTH) AS month                                   -- tanggal awal bulan

FROM `talentiv.final.orders` AS od
LEFT JOIN `talentiv.final.customers` AS cust
  ON od.customer_id = cust.customer_id
LEFT JOIN `talentiv.final.products` AS prod
  ON od.product_id = prod.product_id
WHERE od.order_status = 'Completed'                                           -- buang Returned dan Cancelled
  AND EXTRACT(YEAR FROM od.order_date) BETWEEN 2024 AND 2025;                  -- hanya tahun 2024 dan 2025

select
  category,
  sum(profit) as profit_cat,
  sum(revenue) as revenue_cat
from `talentiv.final.ENRICHED`
group by category;


CREATE OR REPLACE TABLE `talentiv.final.CUSTOMER_SUMMARY` AS
WITH per_customer AS (                             -- rangkum dulu ke level customer
  SELECT
    customer_id,
    COUNT(DISTINCT order_id) AS jumlah_order,
    SUM(revenue) AS total_revenue,
    SUM(profit) AS profit
  FROM `talentiv.final.ENRICHED`
  GROUP BY customer_id
),
spend_tahunan AS (                                 -- spend per tahun + channel
  SELECT
    EXTRACT(YEAR FROM month) AS tahun,
    channel,
    SUM(spend_idr) AS spend_idr
  FROM `talentiv.final.marketing_spend`
  GROUP BY tahun, channel
),
base AS (
  SELECT
    pc.*,
    c.acquisition_channel,
    c.signup_date,
    EXTRACT(YEAR FROM c.signup_date) AS signup_year,
    COALESCE(
      ROUND(sp.spend_idr / COUNT(*) OVER (PARTITION BY EXTRACT(YEAR FROM c.signup_date), c.acquisition_channel), 2),
      0) AS spend_alokasi                          -- spend dibagi rata ke customer, kosong jadi 0
  FROM per_customer AS pc
  LEFT JOIN `talentiv.final.customers` AS c
    ON pc.customer_id = c.customer_id
  LEFT JOIN spend_tahunan AS sp                    -- 1 baris spend per (tahun, channel), baris tidak berlipat
    ON EXTRACT(YEAR FROM c.signup_date) = sp.tahun AND c.acquisition_channel = sp.channel
)
SELECT
  b.customer_id,
  b.jumlah_order,
  b.total_revenue,
  IF(b.jumlah_order = 1, 'Bel Sekali', 'Repeat') AS `Jenis Pelanggan`,
  CASE
    WHEN b.jumlah_order = 1 THEN '1x'
    WHEN b.jumlah_order = 2 THEN '2x'
    WHEN b.jumlah_order = 3 THEN '3x'
    ELSE '4x atau lebih'
  END AS `Kelompok Pelanggan`,
  b.acquisition_channel,
  b.signup_date,
  b.profit,
  b.signup_year,
  1 AS jumlah_pelanggan,                           -- isinya 1 per baris, supaya Sum = jumlah pelanggan
  b.spend_alokasi,
  b.profit - b.spend_alokasi AS profit_setelah_iklan   -- profit dikurangi jatah spend
FROM base AS b
ORDER BY b.jumlah_order, b.total_revenue, b.customer_id;