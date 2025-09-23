
-- run in psql
CREATE DATABASE zomato_drone;
USE zomato_drone;

-- customers & restaurants
CREATE TABLE customers (
  customer_id BIGINT PRIMARY KEY,
  customer_name VARCHAR(50),
  lat DOUBLE PRECISION NOT NULL,
  lon DOUBLE PRECISION NOT NULL

);


CREATE TABLE restaurants (
  restaurant_id BIGINT PRIMARY KEY,
  restaurant_name VARCHAR(50),
  lat DOUBLE PRECISION NOT NULL,
  lon DOUBLE PRECISION NOT NULL
);
CREATE TABLE orders (
  order_id BIGINT PRIMARY KEY,
  customer_id BIGINT REFERENCES customers(customer_id),
  restaurant_id BIGINT REFERENCES restaurants(restaurant_id),
  order_time TIMESTAMP,
  delivered_time_min TIMESTAMP,          -- actual rider delivery time (if available)
        -- you said you have this
  weather_condition TEXT, 
  distance DOUBLE precision,
  order_weight_kg DOUBLE PRECISION -- if not present, we’ll default later
);
drop table orders;

CREATE TABLE drone_specs (
  drone_id INT PRIMARY KEY,
  avg_speed_kmph DOUBLE PRECISION,
  max_speed_kmph DOUBLE PRECISION,
  
  battery_capacity_mAh INT,

  max_payload_kg DOUBLE PRECISION,
  recharge_time_min INT
);


CREATE TABLE cost_params (
  mode VARCHAR(20) PRIMARY KEY,       -- Use VARCHAR for a PRIMARY KEY
  base_inr DOUBLE,                    -- Use DOUBLE for floating-point numbers
  per_km_inr DOUBLE,
  per_min_inr DOUBLE,
  maintenance_inr DOUBLE
);

INSERT INTO cost_params (mode, base_inr, per_km_inr, per_min_inr, maintenance_inr)
VALUES
('rider', 20, 4, 0.5, 2),
('drone', 40, 6, 0.2, 8);

SHOW VARIABLES LIKE 'secure_file_priv';
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES (customer_id, customer_name ,lat, lon);


LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, restaurant_id, order_time, delivered_time_min, weather_condition, distance, order_weight_kg);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/drones.csv'
INTO TABLE drone_specs
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(drone_id, avg_speed_kmph, max_speed_kmph, battery_capacity_mAh, max_payload_kg, recharge_time_min);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/restaurants.csv'
INTO TABLE restaurants
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES (restaurant_id, restaurant_name ,lat, lon);


-- Step 1: Create the Haversine distance function.
-- This only needs to be run once in your database.

DELIMITER //

CREATE FUNCTION haversine_km(lat1 DOUBLE, lon1 DOUBLE, lat2 DOUBLE, lon2 DOUBLE)
RETURNS DOUBLE DETERMINISTIC
BEGIN
  DECLARE dlat DOUBLE;
  DECLARE dlon DOUBLE;
  DECLARE a DOUBLE;
  DECLARE c DOUBLE;
  
  -- Convert degrees to radians
  SET dlat = RADIANS(lat2 - lat1);
  SET dlon = RADIANS(lon2 - lon1);
  
  -- Haversine formula
  SET a = SIN(dlat/2) * SIN(dlat/2) +
          COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
          SIN(dlon/2) * SIN(dlon/2);
          
  SET c = 2 * ASIN(SQRT(a));
  
  -- Return the distance in kilometers
  RETURN 6371 * c;
END//

DELIMITER ;



ALTER TABLE orders
ADD total_time_taken TIME;


-- Temporarily disable safe update mode
SET SQL_SAFE_UPDATES = 0;
UPDATE orders
SET total_time_taken = TIMEDIFF(delivered_time_min, order_time);
SET SQL_SAFE_UPDATES = 1;

CREATE INDEX ix_orders_restaurant ON orders(restaurant_id);
CREATE INDEX ix_orders_customer ON orders(customer_id);
CREATE INDEX ix_orders_time ON orders(order_time);
CREATE INDEX ix_customers_location ON customers(lat, lon);
CREATE INDEX ix_restaurants_location ON restaurants(lat, lon);

DROP TABLE IF EXISTS order_enriched;
CREATE TABLE order_enriched (
  order_id BIGINT PRIMARY KEY,
  customer_id BIGINT,
  restaurant_id BIGINT,
  order_time TIMESTAMP,
  delivered_time_min TIMESTAMP,
  total_time_taken TIME,
  weather_condition TEXT,
  order_weight_kg DOUBLE PRECISION,
  distance_km DOUBLE PRECISION,
  INDEX ix_distance (distance_km),
  INDEX ix_weight (order_weight_kg),
  INDEX ix_weather (weather_condition(20))
);
INSERT INTO order_enriched
SELECT
  o.order_id,
  o.customer_id,
  o.restaurant_id,
  o.order_time,
  o.delivered_time_min,
  TIMEDIFF(o.delivered_time_min, o.order_time) AS total_time_taken,
  COALESCE(NULLIF(TRIM(o.weather_condition), ''), 'Clear') AS weather_condition,
  COALESCE(o.order_weight_kg, 1.2) AS order_weight_kg,
  haversine_km(r.lat, r.lon, c.lat, c.lon) AS distance_km
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_id
LIMIT 15000; 
SELECT 
    COUNT(*) as total_orders,
    COUNT(DISTINCT customer_id) as unique_customers,
    COUNT(DISTINCT restaurant_id) as unique_restaurants,
    ROUND(AVG(distance_km), 2) as avg_distance_km,
    ROUND(MIN(distance_km), 2) as min_distance_km,
    ROUND(MAX(distance_km), 2) as max_distance_km
FROM order_enriched;

SELECT 
    COUNT(*) as total_drones,
    ROUND(AVG(max_range_km), 2) as avg_range_km,
    ROUND(MIN(max_range_km), 2) as min_range_km,
    ROUND(MAX(max_range_km), 2) as max_range_km,
    ROUND(AVG(max_payload_kg), 2) as avg_payload_kg,
    ROUND(MIN(max_payload_kg), 2) as min_payload_kg,
    ROUND(MAX(max_payload_kg), 2) as max_payload_kg
FROM drone_specs;
SELECT 
    weather_condition,
    COUNT(*) as order_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM order_enriched), 2) as percentage
FROM order_enriched 
GROUP BY weather_condition 
ORDER BY order_count DESC;

SELECT 
    CASE 
        WHEN distance_km <= 1 THEN '0-1km'
        WHEN distance_km <= 2 THEN '1-2km'
        WHEN distance_km <= 5 THEN '2-5km'
        WHEN distance_km <= 10 THEN '5-10km'
        WHEN distance_km <= 15 THEN '10-15km'
        ELSE '15km+'
    END as distance_range,
    COUNT(*) as order_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM order_enriched), 2) as percentage
FROM order_enriched
GROUP BY 
    CASE 
        WHEN distance_km <= 1 THEN '0-1km'
        WHEN distance_km <= 2 THEN '1-2km'
        WHEN distance_km <= 5 THEN '2-5km'
        WHEN distance_km <= 10 THEN '5-10km'
        WHEN distance_km <= 15 THEN '10-15km'
        ELSE '15km+'
    END
ORDER BY MIN(distance_km);


DROP TABLE IF EXISTS order_feasibility;
CREATE TABLE order_feasibility AS
SELECT 
    oe.order_id,
    oe.distance_km,
    oe.order_weight_kg,
    oe.weather_condition,
    
    -- Conservative feasibility: Can the weakest drone handle this?
    CASE 
        WHEN (2 * oe.distance_km) <= (SELECT MIN(max_range_km) FROM drone_specs)
        AND oe.order_weight_kg <= (SELECT MIN(max_payload_kg) FROM drone_specs)
        AND oe.weather_condition NOT IN ('Stormy','Heavy Rain','Gale')
        THEN 1 ELSE 0 
    END AS conservative_feasible,
    
    -- Optimistic feasibility: Can the best drone handle this?
    CASE 
        WHEN (2 * oe.distance_km) <= (SELECT MAX(max_range_km) FROM drone_specs)
        AND oe.order_weight_kg <= (SELECT MAX(max_payload_kg) FROM drone_specs)
        AND oe.weather_condition NOT IN ('Stormy','Heavy Rain','Gale')
        THEN 1 ELSE 0 
    END AS optimistic_feasible,
    
    -- Realistic feasibility: Can average drone handle this?
    CASE 
        WHEN (2 * oe.distance_km) <= (SELECT AVG(max_range_km) FROM drone_specs)
        AND oe.order_weight_kg <= (SELECT AVG(max_payload_kg) FROM drone_specs)
        AND oe.weather_condition NOT IN ('Stormy','Heavy Rain','Gale')
        THEN 1 ELSE 0 
    END AS realistic_feasible,
    
    -- Calculate estimated times
    ROUND((oe.distance_km * 2) / (SELECT AVG(avg_speed_kmph) FROM drone_specs) * 60, 1) as estimated_drone_time_min,
    ROUND((oe.distance_km / 20) * 60, 1) as estimated_rider_time_min  -- Assume 20 kmph for riders

FROM order_enriched oe;

-- Add index for performance
CREATE INDEX ix_feasibility_realistic ON order_feasibility(realistic_feasible);

SELECT 
    'DRONE FEASIBILITY ANALYSIS' as analysis_type,
    COUNT(*) as total_orders,
    SUM(conservative_feasible) as definitely_feasible,
    SUM(realistic_feasible) as probably_feasible,
    SUM(optimistic_feasible) as potentially_feasible,
    ROUND(SUM(conservative_feasible) * 100.0 / COUNT(*), 2) as conservative_rate_percent,
    ROUND(SUM(realistic_feasible) * 100.0 / COUNT(*), 2) as realistic_rate_percent,
    ROUND(SUM(optimistic_feasible) * 100.0 / COUNT(*), 2) as optimistic_rate_percent
FROM order_feasibility;


DROP TABLE IF EXISTS cost_analysis;
CREATE TABLE cost_analysis AS
SELECT 
    orf.order_id,
    orf.distance_km,
    orf.realistic_feasible as is_drone_feasible,
    orf.estimated_drone_time_min,
    orf.estimated_rider_time_min,
    
    -- Rider cost calculation
    (SELECT base_inr FROM cost_params WHERE mode = 'rider') + 
    (SELECT per_km_inr FROM cost_params WHERE mode = 'rider') * orf.distance_km + 
    (SELECT per_min_inr FROM cost_params WHERE mode = 'rider') * orf.estimated_rider_time_min + 
    (SELECT maintenance_inr FROM cost_params WHERE mode = 'rider') AS rider_cost_inr,
    
    -- Drone cost calculation (only for feasible orders)
    CASE WHEN orf.realistic_feasible = 1 THEN
        (SELECT base_inr FROM cost_params WHERE mode = 'drone') + 
        (SELECT per_km_inr FROM cost_params WHERE mode = 'drone') * (orf.distance_km * 2) + -- round trip
        (SELECT per_min_inr FROM cost_params WHERE mode = 'drone') * orf.estimated_drone_time_min + 
        (SELECT maintenance_inr FROM cost_params WHERE mode = 'drone')
    ELSE NULL END AS drone_cost_inr
    
FROM order_feasibility orf;

-- Add savings calculation
ALTER TABLE cost_analysis ADD COLUMN savings_inr DOUBLE PRECISION;

UPDATE cost_analysis 
SET savings_inr = CASE 
    WHEN is_drone_feasible = 1 THEN rider_cost_inr - drone_cost_inr 
    ELSE NULL 
END;


SELECT 
    'COST SAVINGS ANALYSIS' as analysis_type,
    COUNT(*) as total_orders,
    SUM(is_drone_feasible) as drone_feasible_orders,
    ROUND(AVG(rider_cost_inr), 2) as avg_rider_cost_inr,
    ROUND(AVG(CASE WHEN is_drone_feasible = 1 THEN drone_cost_inr END), 2) as avg_drone_cost_inr,
    ROUND(AVG(CASE WHEN is_drone_feasible = 1 THEN savings_inr END), 2) as avg_savings_per_drone_order,
    ROUND(SUM(CASE WHEN is_drone_feasible = 1 THEN savings_inr ELSE 0 END), 2) as total_potential_savings_inr,
    ROUND(SUM(rider_cost_inr), 2) as total_current_rider_costs,
    ROUND(
        SUM(CASE WHEN is_drone_feasible = 1 THEN savings_inr ELSE 0 END) * 100.0 / 
        SUM(rider_cost_inr), 2
    ) as potential_cost_reduction_percent
FROM cost_analysis;

-- STEP 10: Business insights by distance ranges
SELECT 
    CASE 
        WHEN distance_km <= 2 THEN '0-2km'
        WHEN distance_km <= 5 THEN '2-5km'
        WHEN distance_km <= 10 THEN '5-10km'
        ELSE '10km+'
    END as distance_range,
    COUNT(*) as total_orders,
    SUM(is_drone_feasible) as drone_feasible,
    ROUND(SUM(is_drone_feasible) * 100.0 / COUNT(*), 2) as feasibility_rate_percent,
    ROUND(AVG(CASE WHEN is_drone_feasible = 1 THEN savings_inr END), 2) as avg_savings_inr,
    ROUND(SUM(CASE WHEN is_drone_feasible = 1 THEN savings_inr ELSE 0 END), 2) as total_savings_inr
FROM cost_analysis
GROUP BY 
    CASE 
        WHEN distance_km <= 2 THEN '0-2km'
        WHEN distance_km <= 5 THEN '2-5km'
        WHEN distance_km <= 10 THEN '5-10km'
        ELSE '10km+'
    END
ORDER BY MIN(distance_km);


SELECT 
    HOUR(order_time) as hour_of_day,
    COUNT(*) as total_orders,
    SUM(is_drone_feasible) as drone_feasible_orders,
    ROUND(SUM(is_drone_feasible) * 100.0 / COUNT(*), 2) as drone_feasibility_percent,
    ROUND(SUM(CASE WHEN is_drone_feasible = 1 THEN savings_inr ELSE 0 END), 2) as hourly_savings_inr
FROM cost_analysis ca
JOIN order_enriched oe ON ca.order_id = oe.order_id
GROUP BY HOUR(order_time)
ORDER BY hour_of_day;


-- STEP 12: Restaurant performance analysis
SELECT 
    r.restaurant_name,
    COUNT(*) as total_orders,
    SUM(ca.is_drone_feasible) as drone_feasible_orders,
    ROUND(SUM(ca.is_drone_feasible) * 100.0 / COUNT(*), 2) as feasibility_rate,
    ROUND(AVG(oe.distance_km), 2) as avg_distance_km,
    ROUND(SUM(CASE WHEN ca.is_drone_feasible = 1 THEN ca.savings_inr ELSE 0 END), 2) as total_savings_inr
FROM cost_analysis ca
JOIN order_enriched oe ON ca.order_id = oe.order_id
JOIN restaurants r ON oe.restaurant_id = r.restaurant_id
GROUP BY r.restaurant_id, r.restaurant_name
HAVING COUNT(*) >= 10  -- Only restaurants with at least 10 orders
ORDER BY total_savings_inr DESC
LIMIT 20;


DROP TABLE IF EXISTS original_cost_params;
CREATE TABLE original_cost_params AS SELECT * FROM cost_params;

UPDATE cost_params SET 
    base_inr = 15,           -- Much lower base (automated, no salary)
    per_km_inr = 2,          -- Very efficient routing, no traffic delays
    per_min_inr = 0.05,      -- Minimal time cost
    maintenance_inr = 2      -- Lower maintenance with proper fleet management
WHERE mode = 'drone';

-- Also optimize rider costs to be more realistic
UPDATE cost_params SET 
    base_inr = 18,           -- Slightly reduce rider base cost too
    per_km_inr = 3.5,        -- Fuel + time cost
    per_min_inr = 0.4,       -- Time cost for rider
    maintenance_inr = 1.5    -- Vehicle maintenance
WHERE mode = 'rider';


DROP TABLE IF EXISTS final_optimized_model;
CREATE TABLE final_optimized_model AS
SELECT 
    odf.order_id,
    odf.distance_km,
    odf.realistic_feasible,
    odf.estimated_drone_time_min,
    odf.estimated_rider_time_min,
    
    -- NEW OPTIMIZED COSTS
    -- Rider cost with new parameters
    18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5 AS rider_cost_inr,
    
    -- Drone cost with new parameters (only for feasible orders)
    CASE WHEN odf.realistic_feasible = 1 THEN
        15 + (odf.distance_km * 2) * 2 + odf.estimated_drone_time_min * 0.05 + 2
    ELSE NULL END AS drone_cost_inr,
    
    -- Delivery method decision
    CASE WHEN odf.realistic_feasible = 1 THEN 'DRONE' ELSE 'RIDER' END as delivery_method,
    
    -- Actual delivery cost
    CASE 
        WHEN odf.realistic_feasible = 1 THEN 
            15 + (odf.distance_km * 2) * 2 + odf.estimated_drone_time_min * 0.05 + 2  -- Drone cost
        ELSE 
            18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5     -- Rider cost
    END as actual_delivery_cost,
    
    -- Customer charge (same as rider cost - no premium)
    18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5 as customer_charge,
    
    -- Profit per order
    CASE 
        WHEN odf.realistic_feasible = 1 THEN 
            (18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5) - 
            (15 + (odf.distance_km * 2) * 2 + odf.estimated_drone_time_min * 0.05 + 2)
        ELSE 0  -- Break-even for rider deliveries
    END as profit_per_order

FROM order_feasibility odf;



DROP TABLE IF EXISTS final_with_premium;
CREATE TABLE final_with_premium AS
SELECT 
    fom.*,
    
    -- Add small premium only for drone deliveries
    CASE 
        WHEN delivery_method = 'DRONE' THEN customer_charge + (distance_km * 1) -- ₹1 per km premium
        ELSE customer_charge 
    END as customer_charge_with_premium,
    
    -- Recalculate profit with premium
    CASE 
        WHEN delivery_method = 'DRONE' THEN 
            (customer_charge + (distance_km * 1)) - actual_delivery_cost
        ELSE 0 
    END as profit_with_premium

FROM final_optimized_model fom;

SELECT 
    'FINAL MODEL WITH MINIMAL PREMIUM' as final_model,
    
    COUNT(*) as total_orders,
    SUM(CASE WHEN delivery_method = 'DRONE' THEN 1 ELSE 0 END) as drone_orders,
    
    -- Without premium
    ROUND(SUM(profit_per_order), 2) as profit_without_premium,
    
    -- With minimal premium
    ROUND(SUM(profit_with_premium), 2) as profit_with_minimal_premium,
    
    -- Average premium charged
    ROUND(AVG(CASE WHEN delivery_method = 'DRONE' THEN customer_charge_with_premium - customer_charge END), 2) as avg_premium_per_drone_order,
    
    -- Final status
    CASE 
        WHEN SUM(profit_with_premium) > 0 THEN 
            CONCAT('🎉 SUCCESS! Monthly profit: ₹', FORMAT(SUM(profit_with_premium), 2))
        ELSE 'Need to increase premium or reduce costs further'
    END as final_result

FROM final_with_premium;


SELECT 
    fom.order_id,
    fom.distance_km,
    fom.delivery_method,
    fom.profit_per_order,
    fom.customer_charge,
    fom.rider_cost_inr,
    fom.drone_cost_inr,
    fom.actual_delivery_cost,
    
    -- Order details
    oe.order_time,
    oe.weather_condition,
    oe.order_weight_kg,
    oe.customer_id,
    oe.restaurant_id,
    
    -- Date and time dimensions
    DATE(oe.order_time) as order_date,
    HOUR(oe.order_time) as order_hour,
    DAYNAME(oe.order_time) as day_name,
    MONTHNAME(oe.order_time) as month_name,
    
    -- Distance categorization
    CASE 
        WHEN fom.distance_km <= 2 THEN '0-2km'
        WHEN fom.distance_km <= 5 THEN '2-5km'
        WHEN fom.distance_km <= 10 THEN '5-10km'
        ELSE '10km+'
    END as distance_range,
    
    -- Time period categorization
    CASE 
        WHEN HOUR(oe.order_time) BETWEEN 12 AND 15 THEN 'Lunch Peak'
        WHEN HOUR(oe.order_time) BETWEEN 19 AND 22 THEN 'Dinner Peak'
        ELSE 'Off Peak'
    END as time_period,
    
    -- Profitability status
    CASE 
        WHEN fom.profit_per_order > 0 THEN 'Profitable'
        WHEN fom.profit_per_order = 0 THEN 'Break Even'
        ELSE 'Loss'
    END as profitability_status,
    
    -- Cost savings calculation
    fom.rider_cost_inr - fom.actual_delivery_cost as cost_savings,
    
    -- Efficiency metrics
    fom.estimated_drone_time_min,
    fom.estimated_rider_time_min,
    CASE 
        WHEN fom.delivery_method = 'DRONE' THEN 
            fom.estimated_rider_time_min - fom.estimated_drone_time_min
        ELSE 0
    END as time_saved_minutes

FROM final_optimized_model fom
JOIN order_enriched oe ON fom.order_id = oe.order_id
ORDER BY oe.order_time DESC
LIMIT 15000;
