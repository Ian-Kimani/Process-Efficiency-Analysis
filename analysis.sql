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
