-- =====================================================================
-- Olist E-commerce Analysis: SQL queries (SQLite)
-- Each query starts with a "-- name:" line so the notebook can load it.
-- Revenue = product price (excluding freight) on DELIVERED orders only.
-- =====================================================================

-- name: overview
-- Q0. Headline numbers for delivered orders
WITH order_value AS (
    SELECT order_id,
           SUM(price)                 AS product_value,
           SUM(price + freight_value) AS order_value
    FROM order_items
    GROUP BY order_id
)
SELECT COUNT(DISTINCT o.order_id)            AS delivered_orders,
       COUNT(DISTINCT c.customer_unique_id)   AS unique_customers,
       ROUND(SUM(v.product_value), 0)         AS revenue_brl,
       ROUND(AVG(v.order_value), 2)           AS avg_order_value_brl
FROM orders o
JOIN order_value v ON v.order_id = o.order_id
JOIN customers  c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered';

-- name: monthly_trend
-- Q1. How did orders and revenue grow month by month?
SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS month,
       COUNT(DISTINCT o.order_id)                   AS orders,
       ROUND(SUM(i.price), 0)                       AS revenue_brl
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
GROUP BY month
ORDER BY month;

-- name: category_pareto
-- Q2. Which product categories drive revenue? (running share with a window function)
WITH cat AS (
    SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'uncategorised') AS category,
           SUM(i.price)               AS revenue_brl,
           COUNT(DISTINCT i.order_id) AS orders
    FROM order_items i
    JOIN orders   o ON o.order_id   = i.order_id
    JOIN products p ON p.product_id = i.product_id
    LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY category
)
SELECT category,
       ROUND(revenue_brl, 0) AS revenue_brl,
       orders,
       ROUND(100.0 * revenue_brl / SUM(revenue_brl) OVER (), 1) AS share_pct,
       ROUND(100.0 * SUM(revenue_brl) OVER (ORDER BY revenue_brl DESC)
                   / SUM(revenue_brl) OVER (), 1)                AS cumulative_share_pct,
       RANK() OVER (ORDER BY revenue_brl DESC)                    AS revenue_rank
FROM cat
ORDER BY revenue_brl DESC;

-- name: state_delivery
-- Q3. Where are deliveries slowest and most often late?
SELECT c.customer_state AS state,
       COUNT(*)         AS orders,
       ROUND(AVG(julianday(o.order_delivered_customer_date)
               - julianday(o.order_purchase_timestamp)), 1)                      AS avg_delivery_days,
       ROUND(100.0 * AVG(o.order_delivered_customer_date > o.order_estimated_delivery_date), 1) AS late_pct
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY state
HAVING COUNT(*) >= 300
ORDER BY avg_delivery_days DESC;

-- name: late_vs_reviews
-- Q4. Does late delivery hurt customer reviews?
WITH review AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
),
delay AS (
    SELECT o.order_id,
           julianday(date(o.order_delivered_customer_date))
         - julianday(date(o.order_estimated_delivery_date)) AS days_late
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT CASE
         WHEN d.days_late <= 0  THEN '1. On time'
         WHEN d.days_late <= 3  THEN '2. 1-3 days late'
         WHEN d.days_late <= 7  THEN '3. 4-7 days late'
         WHEN d.days_late <= 14 THEN '4. 8-14 days late'
         ELSE                        '5. 15+ days late'
       END                                     AS delivery_bucket,
       COUNT(*)                                AS orders,
       ROUND(AVG(r.score), 2)                  AS avg_review,
       ROUND(100.0 * AVG(r.score <= 2), 1)     AS pct_1_or_2_star
FROM delay d
JOIN review r ON r.order_id = d.order_id
GROUP BY delivery_bucket
ORDER BY delivery_bucket;

-- name: repeat_customers
-- Q5. How many customers come back for a second order?
WITH per_customer AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS n_orders
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT CASE WHEN n_orders >= 3 THEN '3+' ELSE CAST(n_orders AS TEXT) END AS orders_per_customer,
       COUNT(*)                                                      AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)            AS pct_customers
FROM per_customer
GROUP BY orders_per_customer
ORDER BY orders_per_customer;

-- name: payments
-- Q6. How do customers pay?
SELECT payment_type,
       COUNT(*)                                            AS payments,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS share_pct,
       ROUND(AVG(payment_installments), 1)                 AS avg_installments,
       ROUND(AVG(payment_value), 2)                        AS avg_value_brl
FROM order_payments
WHERE payment_type <> 'not_defined'
GROUP BY payment_type
ORDER BY payments DESC;
