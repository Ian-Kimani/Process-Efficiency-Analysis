SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    c.customer_state,
    s.seller_state
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN sellers s
    ON oi.seller_id = s.seller_id
WHERE
    o.order_status = 'delivered'
    AND o.order_delivered_customer_date IS NOT NULL;



-- To check where delays happen, where time is maintained,, etc
WITH joined_orders AS (
    SELECT
        o.order_id,

        o.order_purchase_timestamp::timestamp AS order_purchase_ts,
        o.order_approved_at::timestamp AS order_approved_ts,
        o.order_delivered_carrier_date::timestamp AS carrier_delivered_ts,
        o.order_delivered_customer_date::timestamp AS customer_delivered_ts,
        o.order_estimated_delivery_date::timestamp AS estimated_delivery_ts,

        c.customer_state,
        s.seller_state
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN sellers s
        ON oi.seller_id = s.seller_id
    WHERE
        o.order_status = 'delivered'
        AND o.order_delivered_customer_date IS NOT NULL
)

SELECT
    order_id,
    customer_state,
    seller_state,

    customer_delivered_ts - order_purchase_ts
        AS total_fulfillment_time,

    order_approved_ts - order_purchase_ts
        AS approval_time,

    carrier_delivered_ts - order_approved_ts
        AS shipping_prep_time,

    customer_delivered_ts - carrier_delivered_ts
        AS delivery_time,

    CASE
        WHEN customer_delivered_ts > estimated_delivery_ts
        THEN 1 ELSE 0
    END AS is_late
FROM joined_orders;

SELECT
    COUNT(*) AS total_rows,
    COUNT(order_approved_at) AS approved_present,
    COUNT(order_delivered_carrier_date) AS carrier_present
FROM orders;


SELECT
    order_status,
    COUNT(*) AS count
FROM orders
GROUP BY order_status
ORDER BY count DESC;

SELECT
    COUNT(*) AS approved_orders,
    COUNT(order_delivered_customer_date) AS delivered_orders
FROM orders
WHERE order_approved_at IS NOT NULL;

-- a failure dataset to know the cancelled orders
SELECT *
FROM orders
WHERE order_status = 'canceled';

-- Check whether the orders were cancelled before or after approval
SELECT
    COUNT(*) AS total_cancelled,
    COUNT(order_approved_at) AS approved_before_cancel
FROM orders
WHERE order_status = 'canceled';
-- 484 orders were cancelled after approval

-- Does cancellation correlate with price
-- if cancelled orders are more expensive - seller failure
SELECT 
    AVG(oi.price) AS avg_price
FROM orders o
JOIN order_items oi
ON o.order_id = oi.order_id; 

SELECT 
    MAX(price) AS max_price
FROM order_items;

SELECT 
    price AS prices
FROM order_items; 
 

SELECT
    AVG(oi.price) AS avg_price
FROM orders o
JOIN order_items oi
ON o.order_id = oi.order_id
WHERE o.order_status = 'canceled';

-- The whole average price was 120, the cancelled average price was 175
-- many cancelled orders,, their prices were higher than the average price

-- Are cancellations tied to a certain region??
-- Can show that maybe infrastructure, distance , security etc
SELECT
    c.customer_state,
    COUNT(*) AS cancellations
FROM orders o
JOIN customers c
ON o.customer_id = c.customer_id
WHERE o.order_status = 'canceled'
GROUP BY c.customer_state
ORDER BY cancellations DESC;
-- yes alot of cancellations happen in SP state

SELECT customer_state,
    COUNT(*) AS count
FROM customers 
GROUP BY customer_state
ORDER BY count DESC;

WITH state_totals AS (
    SELECT
        c.customer_state,
        COUNT(*) AS total_orders
    FROM orders o
    JOIN customers c
    ON o.customer_id = c.customer_id
    GROUP BY c.customer_state
),
state_cancellations AS (
    SELECT
        c.customer_state,
        COUNT(*) AS cancelled_orders
    FROM orders o
    JOIN customers c
    ON o.customer_id = c.customer_id
    WHERE o.order_status = 'canceled'
    GROUP BY c.customer_state
)
SELECT
    t.customer_state,
    cancelled_orders,
    total_orders,
    (cancelled_orders::float / total_orders) * 100 AS cancellation_percentage_rate
FROM state_totals t
JOIN state_cancellations s
ON t.customer_state = s.customer_state
ORDER BY cancellation_percentage_rate DESC;



-- Do certain sellers cancel more?
SELECT
    oi.seller_id,
    COUNT(*) AS cancellations
FROM orders o
JOIN order_items oi
ON o.order_id = oi.order_id
WHERE o.order_status = 'canceled'
GROUP BY oi.seller_id
ORDER BY cancellations DESC
LIMIT 10;

SELECT *
FROM orders
WHERE order_status = 'canceled'
;

-- Time taken to cancel orders
SELECT
    CASE
        WHEN order_approved_at IS NULL THEN 'cancelled_before_approval'
        ELSE 'cancelled_after_approval'
    END AS cancel_stage,
    COUNT(*) AS orders
FROM orders
WHERE order_status = 'canceled'
GROUP BY cancel_stage;
-- This shows there is a seller/ logistics failure


-- Checks the time used for orders to be approved between cancelled and delivered orders
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY order_approved_at::timestamp - order_purchase_timestamp::timestamp
    ) AS median_time_to_approval
FROM orders
WHERE order_status = 'canceled'
AND order_approved_at IS NOT NULL;


SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY order_approved_at::timestamp - order_purchase_timestamp::timestamp
    ) AS median_time_to_approval
FROM orders
WHERE order_status = 'delivered'
AND order_approved_at IS NOT NULL;

-- cancelled orders take on average 19:42.5 and delivered 20.36


-- Late stage cancellation
-- cancelled orders should not reach carrier or customer
SELECT
    COUNT(*) AS suspicious_cancellations
FROM orders
WHERE order_status = 'canceled'
AND (
    order_delivered_carrier_date IS NOT NULL
    OR order_delivered_customer_date IS NOT NULL
);
-- Approximately 12% of cancelled orders show downstream delivery activity, indicating potential inconsistencies between order status and logistics events
-- showing its either asynchromous updates colliding, partial shipments, late cancellations or bad rreconcilliation between services

-- The dataset does not provide an explicit cancellation timestamp.Therefore, cancellation timing was inferred using approval and purchase timestamps as upper-bound proxies.Findings should be interpreted as indicative rather than exact

SELECT
    order_id,
    order_status,
    (order_approved_at IS NOT NULL)::int AS approved,
    (order_delivered_carrier_date IS NOT NULL)::int AS sent_to_carrier,
    (order_delivered_customer_date IS NOT NULL)::int AS delivered
FROM orders;

SELECT
    order_status,
    AVG((order_approved_at IS NOT NULL)::int) AS approval_rate,
    AVG((order_delivered_carrier_date IS NOT NULL)::int) AS carrier_rate,
    AVG((order_delivered_customer_date IS NOT NULL)::int) AS delivery_rate
FROM orders
WHERE order_status IN ('delivered', 'canceled')
GROUP BY order_status;

SELECT
    COUNT(*) AS impossible_orders
FROM orders
WHERE order_status = 'canceled'
AND order_delivered_customer_date IS NOT NULL;

SELECT
    order_status,
    AVG(order_estimated_delivery_date - order_purchase_timestamp) AS avg_estimated_window
FROM orders
WHERE order_status IN ('delivered', 'canceled')
GROUP BY order_status;


-- DELIVERY PERFORMANCE

-- Delivered orders
SELECT *
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NOT NULL
AND order_estimated_delivery_date IS NOT NULL;

SELECT
    (order_delivered_customer_date::timestamp - order_estimated_delivery_date::timestamp) AS delivery_delay
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NOT NULL
AND order_estimated_delivery_date IS NOT NULL
AND (order_delivered_customer_date::timestamp - order_estimated_delivery_date::timestamp) > 0;

SELECT
    COUNT(*) AS total_delivered,
    AVG(
        CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date
        THEN 1 ELSE 0 END
    ) AS on_time_rate
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NOT NULL
AND order_estimated_delivery_date IS NOT NULL;

SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY order_delivered_customer_date - order_estimated_delivery_date
    ) AS median_delay,
    PERCENTILE_CONT(0.9) WITHIN GROUP (
        ORDER BY order_delivered_customer_date - order_estimated_delivery_date
    ) AS p90_delay
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date > order_estimated_delivery_date;

SELECT
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date
        THEN 'on_or_early'
        ELSE 'late'
    END AS delivery_group,
    COUNT(*) AS orders
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NOT NULL
AND order_estimated_delivery_date IS NOT NULL
GROUP BY delivery_group;
