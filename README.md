Zomato Drone Delivery Analytics
Project Overview

This project analyzes the feasibility and cost optimization of implementing drone delivery for Zomato's food delivery service. It includes comprehensive database modeling, feasibility and cost analysis, and location-based delivery optimization using SQL and Python.

Key Features
Database Schema

Customers & Restaurants: Stores location data with GPS coordinates.

Orders: Manages all order information including timing, weather, and distance.

Drone Specifications: Contains details about drone speed, payload, and battery.

Cost Parameters: Defines cost structures for both rider and drone deliveries.

Analytics Components

Feasibility Analysis: Determines which orders can be delivered by drones.

Cost Optimization: Compares costs of drone versus rider deliveries.

Location Intelligence: Identifies feasible delivery zones.

Weather Impact: Analyzes weather effects on drone delivery.

Performance Metrics: Generates efficiency and profitability insights.

Project Structure
Zomato-drone-delivery/
├── zomato.sql                # Database schema and analysis queries
├── connect_mysql.py          # MySQL connection and export script
├── export_instructions.md    # Guide for data export
└── README.md                 # Project documentation

Setup Instructions
Prerequisites

MySQL Server 8.0 or later

MySQL Workbench (optional)

Python 3.7+ with mysql-connector-python and pandas installed

Database Setup
CREATE DATABASE zomato_drone;
USE zomato_drone;


Run all the SQL statements below (from schema creation to analysis).

Database Schema and SQL Queries
1. Table Creation
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
  delivered_time_min TIMESTAMP,
  weather_condition TEXT,
  distance DOUBLE PRECISION,
  order_weight_kg DOUBLE PRECISION
);

CREATE TABLE drone_specs (
  drone_id INT PRIMARY KEY,
  avg_speed_kmph DOUBLE PRECISION,
  max_speed_kmph DOUBLE PRECISION,
  battery_capacity_mAh INT,
  max_payload_kg DOUBLE PRECISION,
  recharge_time_min INT
);

CREATE TABLE cost_params (
  mode VARCHAR(20) PRIMARY KEY,
  base_inr DOUBLE,
  per_km_inr DOUBLE,
  per_min_inr DOUBLE,
  maintenance_inr DOUBLE
);

INSERT INTO cost_params (mode, base_inr, per_km_inr, per_min_inr, maintenance_inr)
VALUES
('rider', 20, 4, 0.5, 2),
('drone', 40, 6, 0.2, 8);

2. Distance Calculation Function (Haversine Formula)
DELIMITER //

CREATE FUNCTION haversine_km(lat1 DOUBLE, lon1 DOUBLE, lat2 DOUBLE, lon2 DOUBLE)
RETURNS DOUBLE DETERMINISTIC
BEGIN
  DECLARE dlat DOUBLE;
  DECLARE dlon DOUBLE;
  DECLARE a DOUBLE;
  DECLARE c DOUBLE;

  SET dlat = RADIANS(lat2 - lat1);
  SET dlon = RADIANS(lon2 - lon1);
  SET a = SIN(dlat/2) * SIN(dlat/2) +
          COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
          SIN(dlon/2) * SIN(dlon/2);
  SET c = 2 * ASIN(SQRT(a));
  RETURN 6371 * c;
END//

DELIMITER ;

3. Data Enrichment and Indexing
ALTER TABLE orders ADD total_time_taken TIME;

SET SQL_SAFE_UPDATES = 0;
UPDATE orders
SET total_time_taken = TIMEDIFF(delivered_time_min, order_time);
SET SQL_SAFE_UPDATES = 1;

CREATE INDEX ix_orders_restaurant ON orders(restaurant_id);
CREATE INDEX ix_orders_customer ON orders(customer_id);
CREATE INDEX ix_orders_time ON orders(order_time);
CREATE INDEX ix_customers_location ON customers(lat, lon);
CREATE INDEX ix_restaurants_location ON restaurants(lat, lon);

CREATE TABLE order_enriched AS
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

4. Feasibility Analysis
CREATE TABLE order_feasibility AS
SELECT 
    oe.order_id,
    oe.distance_km,
    oe.order_weight_kg,
    oe.weather_condition,
    CASE 
        WHEN (2 * oe.distance_km) <= (SELECT MIN(max_range_km) FROM drone_specs)
        AND oe.order_weight_kg <= (SELECT MIN(max_payload_kg) FROM drone_specs)
        AND oe.weather_condition NOT IN ('Stormy','Heavy Rain','Gale')
        THEN 1 ELSE 0 
    END AS conservative_feasible,
    CASE 
        WHEN (2 * oe.distance_km) <= (SELECT MAX(max_range_km) FROM drone_specs)
        AND oe.order_weight_kg <= (SELECT MAX(max_payload_kg) FROM drone_specs)
        AND oe.weather_condition NOT IN ('Stormy','Heavy Rain','Gale')
        THEN 1 ELSE 0 
    END AS optimistic_feasible,
    CASE 
        WHEN (2 * oe.distance_km) <= (SELECT AVG(max_range_km) FROM drone_specs)
        AND oe.order_weight_kg <= (SELECT AVG(max_payload_kg) FROM drone_specs)
        AND oe.weather_condition NOT IN ('Stormy','Heavy Rain','Gale')
        THEN 1 ELSE 0 
    END AS realistic_feasible,
    ROUND((oe.distance_km * 2) / (SELECT AVG(avg_speed_kmph) FROM drone_specs) * 60, 1) as estimated_drone_time_min,
    ROUND((oe.distance_km / 20) * 60, 1) as estimated_rider_time_min
FROM order_enriched oe;

5. Cost Analysis
CREATE TABLE cost_analysis AS
SELECT 
    orf.order_id,
    orf.distance_km,
    orf.realistic_feasible as is_drone_feasible,
    orf.estimated_drone_time_min,
    orf.estimated_rider_time_min,
    (SELECT base_inr FROM cost_params WHERE mode = 'rider') + 
    (SELECT per_km_inr FROM cost_params WHERE mode = 'rider') * orf.distance_km + 
    (SELECT per_min_inr FROM cost_params WHERE mode = 'rider') * orf.estimated_rider_time_min + 
    (SELECT maintenance_inr FROM cost_params WHERE mode = 'rider') AS rider_cost_inr,
    CASE WHEN orf.realistic_feasible = 1 THEN
        (SELECT base_inr FROM cost_params WHERE mode = 'drone') + 
        (SELECT per_km_inr FROM cost_params WHERE mode = 'drone') * (orf.distance_km * 2) + 
        (SELECT per_min_inr FROM cost_params WHERE mode = 'drone') * orf.estimated_drone_time_min + 
        (SELECT maintenance_inr FROM cost_params WHERE mode = 'drone')
    ELSE NULL END AS drone_cost_inr
FROM order_feasibility orf;

ALTER TABLE cost_analysis ADD COLUMN savings_inr DOUBLE PRECISION;

UPDATE cost_analysis 
SET savings_inr = CASE 
    WHEN is_drone_feasible = 1 THEN rider_cost_inr - drone_cost_inr 
    ELSE NULL 
END;

6. Final Optimized Model
CREATE TABLE final_optimized_model AS
SELECT 
    odf.order_id,
    odf.distance_km,
    odf.realistic_feasible,
    odf.estimated_drone_time_min,
    odf.estimated_rider_time_min,
    18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5 AS rider_cost_inr,
    CASE WHEN odf.realistic_feasible = 1 THEN
        15 + (odf.distance_km * 2) * 2 + odf.estimated_drone_time_min * 0.05 + 2
    ELSE NULL END AS drone_cost_inr,
    CASE WHEN odf.realistic_feasible = 1 THEN 'DRONE' ELSE 'RIDER' END as delivery_method,
    CASE 
        WHEN odf.realistic_feasible = 1 THEN 
            15 + (odf.distance_km * 2) * 2 + odf.estimated_drone_time_min * 0.05 + 2
        ELSE 
            18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5
    END as actual_delivery_cost,
    18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5 as customer_charge,
    CASE 
        WHEN odf.realistic_feasible = 1 THEN 
            (18 + odf.distance_km * 3.5 + odf.estimated_rider_time_min * 0.4 + 1.5) - 
            (15 + (odf.distance_km * 2) * 2 + odf.estimated_drone_time_min * 0.05 + 2)
        ELSE 0  
    END as profit_per_order
FROM order_feasibility odf;

7. Final Model with Premium
CREATE TABLE final_with_premium AS
SELECT 
    fom.*,
    CASE 
        WHEN delivery_method = 'DRONE' THEN customer_charge + (distance_km * 1)
        ELSE customer_charge 
    END as customer_charge_with_premium,
    CASE 
        WHEN delivery_method = 'DRONE' THEN 
            (customer_charge + (distance_km * 1)) - actual_delivery_cost
        ELSE 0 
    END as profit_with_premium
FROM final_optimized_model fom;

Business Insights

Short distance orders (0–2 km): Most feasible and profitable for drones.

Medium distances (2–5 km): Moderate feasibility, good profit margins.

Long distances (5 km+): Less feasible for drones; prefer riders.

Clear weather increases drone delivery feasibility up to 100%.
