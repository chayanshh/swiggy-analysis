-- ============================================================
                     -- SWIGGY ANALYTICS — 

-- ============================================================

CREATE DATABASE IF NOT EXISTS swiggy_analytics;
USE swiggy_analytics;

-- ============================================================
-- STEP 1: CREATE TABLES (Star Schema)
-- ============================================================

CREATE TABLE dim_date (
    date_id     INT PRIMARY KEY,
    order_date  DATE NOT NULL,
    month       INT,
    month_name  VARCHAR(10),
    year        INT,
    day_of_week VARCHAR(12),
    quarter     INT
);

CREATE TABLE dim_restaurant (
    restaurant_id   INT PRIMARY KEY,
    restaurant_name VARCHAR(255)
);

CREATE TABLE dim_location (
    location_id INT PRIMARY KEY,
    state       VARCHAR(100),
    city        VARCHAR(100),
    location    VARCHAR(255)
);

CREATE TABLE dim_dish (
    dish_id   INT PRIMARY KEY,
    category  VARCHAR(200),
    dish_name VARCHAR(300)
);

CREATE TABLE fact_orders (
    order_id      INT PRIMARY KEY,
    date_id       INT,
    location_id   INT,
    restaurant_id INT,
    food_id       INT,
    price         DECIMAL(10,2),
    rating        DECIMAL(3,1),
    rating_count  INT,
    price_tier    VARCHAR(20),
    is_anomaly    TINYINT DEFAULT 0,
    is_zero_review TINYINT DEFAULT 0,
    FOREIGN KEY (date_id)       REFERENCES dim_date(date_id),
    FOREIGN KEY (location_id)   REFERENCES dim_location(location_id),
    FOREIGN KEY (restaurant_id) REFERENCES dim_restaurant(restaurant_id),
    FOREIGN KEY (food_id)       REFERENCES dim_dish(dish_id)
);

-- ============================================================
-- STEP 2: LOAD DATA
-- (Update file paths to match your local machine)
-- ============================================================

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'E:/Swiggy/dim_date_clean.csv'
INTO TABLE dim_date 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n' 
IGNORE 1 ROWS;

truncate dim_restaurant;
LOAD DATA LOCAL INFILE 'E:/Swiggy/dim_restaurant.csv'
INTO TABLE dim_restaurant 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
 IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'E:/Swiggy/dim_location.csv'
INTO TABLE dim_location 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' 
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'E:/Swiggy/dim_dish.csv'
INTO TABLE dim_dish 
FIELDS TERMINATED BY ','
 ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' 
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'E:/Swiggy/fact_orders_clean.csv'
INTO TABLE fact_orders 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' 
IGNORE 1 ROWS;

select * from fact_orders;
select * from dim_date;
select * from dim_dish;
select * from dim_location;
select * from dim_restaurant;

-- ============================================================
-- STEP 3: ADD INDEXES
-- ============================================================

CREATE INDEX idx_fact_date     ON fact_orders(date_id);
CREATE INDEX idx_fact_location ON fact_orders(location_id);
CREATE INDEX idx_fact_rest     ON fact_orders(restaurant_id);
CREATE INDEX idx_fact_food     ON fact_orders(food_id);
CREATE INDEX idx_fact_rating   ON fact_orders(rating);
CREATE INDEX idx_fact_price    ON fact_orders(price);
CREATE INDEX idx_fact_anomaly  ON fact_orders(is_anomaly);

-- ============================================================
-- STEP 4: KPI QUERIES
-- ============================================================

-- KPI 1: Revenue Concentration Ratio
WITH restaurant_revenue AS (
    SELECT restaurant_id, SUM(price) AS revenue
    FROM fact_orders GROUP BY restaurant_id
),
ranked AS (
    SELECT *, PERCENT_RANK() OVER (ORDER BY revenue DESC) AS pct_rank
    FROM restaurant_revenue
)
SELECT
    ROUND(SUM(CASE WHEN pct_rank <= 0.10 THEN revenue ELSE 0 END) /
    SUM(revenue) * 100, 2) AS revenue_concentration_pct
FROM ranked;

-- KPI 2: Month-over-Month Revenue
SELECT d.month_name, d.year, d.month,
       COUNT(f.order_id) AS orders,
       ROUND(SUM(f.price), 2) AS monthly_revenue,
       ROUND((SUM(f.price) - LAG(SUM(f.price)) OVER (ORDER BY d.year, d.month)) /
             LAG(SUM(f.price)) OVER (ORDER BY d.year, d.month) * 100, 2) AS mom_growth_pct
FROM fact_orders f JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.year, d.month, d.month_name;

-- KPI 3: Low Rating Restaurants (below 3.5)
SELECT r.restaurant_name,
       ROUND(AVG(f.rating), 2) AS avg_rating,
       COUNT(*) AS total_orders
FROM fact_orders f JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY f.restaurant_id, r.restaurant_name
HAVING avg_rating < 3.5
ORDER BY avg_rating ASC;

-- KPI 4: Zero-Review Restaurant Rate
SELECT
    SUM(CASE WHEN max_rc = 0 THEN 1 ELSE 0 END) AS zero_review_restaurants,
    COUNT(*) AS total_restaurants,
    ROUND(SUM(CASE WHEN max_rc = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS zero_review_rate_pct
FROM (
    SELECT restaurant_id, MAX(rating_count) AS max_rc
    FROM fact_orders GROUP BY restaurant_id
) t;

-- KPI 5: Rating Quality Index
SELECT r.restaurant_name,
       ROUND(AVG(f.rating), 2) AS avg_rating,
       ROUND(AVG(f.rating_count), 1) AS avg_review_count,
       ROUND(AVG(f.rating) * LOG10(1 + AVG(f.rating_count)), 3) AS rating_quality_index
FROM fact_orders f JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY f.restaurant_id, r.restaurant_name
ORDER BY rating_quality_index DESC;

-- KPI 6: Category Revenue Share
SELECT d.category,
       COUNT(f.order_id) AS orders,
       ROUND(SUM(f.price), 2) AS revenue,
       ROUND(SUM(f.price) * 100.0 / (SELECT SUM(price) FROM fact_orders), 2) AS revenue_share_pct,
       ROUND(AVG(f.rating), 2) AS avg_rating
FROM fact_orders f JOIN dim_dish d ON f.food_id = d.dish_id
GROUP BY d.category ORDER BY revenue DESC;

-- KPI 7: High Price + Low Rating Anomaly Rate
SELECT
    SUM(is_anomaly) AS anomaly_orders,
    COUNT(*) AS total_orders,
    ROUND(SUM(is_anomaly) * 100.0 / COUNT(*), 3) AS anomaly_rate_pct,
    ROUND(AVG(CASE WHEN is_anomaly = 1 THEN price END), 2) AS avg_anomaly_price
FROM fact_orders;

-- KPI 8: City Order Density Index
SELECT l.city, l.state,
       COUNT(f.order_id) AS total_orders,
       COUNT(DISTINCT l.location_id) AS localities,
       ROUND(COUNT(f.order_id) * 1.0 / COUNT(DISTINCT l.location_id), 1) AS order_density,
       ROUND(SUM(f.price) / COUNT(DISTINCT l.location_id), 2) AS revenue_per_locality
FROM fact_orders f JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.city, l.state ORDER BY order_density DESC;

-- KPI 9: State Revenue-Quality Composite Score
WITH state_stats AS (
    SELECT l.state, SUM(f.price) AS total_revenue,
           AVG(f.rating) AS avg_rating, COUNT(f.order_id) AS orders
    FROM fact_orders f JOIN dim_location l ON f.location_id = l.location_id
    GROUP BY l.state
),
bounds AS (
    SELECT MIN(total_revenue) min_r, MAX(total_revenue) max_r,
           MIN(avg_rating) min_q, MAX(avg_rating) max_q FROM state_stats
),
normalised AS (
    SELECT s.state, s.total_revenue, s.avg_rating, s.orders,
           (s.total_revenue - b.min_r) / NULLIF(b.max_r - b.min_r, 0) AS norm_rev,
           (s.avg_rating - b.min_q) / NULLIF(b.max_q - b.min_q, 0) AS norm_rat
    FROM state_stats s, bounds b
)
SELECT state, orders,
       ROUND(total_revenue / 1000000, 3) AS revenue_M,
       ROUND(avg_rating, 3) AS avg_rating,
       ROUND(norm_rev * 0.6 + norm_rat * 0.4, 3) AS composite_score,
       CASE
           WHEN norm_rev >= 0.5 AND norm_rat >= 0.5 THEN 'DEFEND'
           WHEN norm_rev < 0.5  AND norm_rat >= 0.5 THEN 'INVEST'
           WHEN norm_rev >= 0.5 AND norm_rat < 0.5  THEN 'IMPROVE'
           ELSE 'REVIEW'
       END AS quadrant
FROM normalised ORDER BY composite_score DESC;

-- KPI 10: Peak Day Revenue
SELECT d.order_date, d.day_of_week,
       COUNT(f.order_id) AS daily_orders,
       ROUND(SUM(f.price), 2) AS daily_revenue,
       ROUND(COUNT(f.order_id) * 100.0 / (SELECT COUNT(*) FROM fact_orders), 3) AS pct_of_total
FROM fact_orders f JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.order_date, d.day_of_week
ORDER BY daily_orders DESC
LIMIT 20;

-- ============================================================
-- STEP 5: CREATE VIEWS FOR POWER BI
-- ============================================================

CREATE OR REPLACE VIEW vw_monthly_revenue AS
SELECT d.year, d.month, d.month_name,
       COUNT(f.order_id) AS orders,
       ROUND(SUM(f.price), 2) AS revenue
FROM fact_orders f JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.year, d.month, d.month_name;

CREATE OR REPLACE VIEW vw_category_performance AS
SELECT d.category,
       COUNT(f.order_id) AS orders,
       ROUND(SUM(f.price), 2) AS revenue,
       ROUND(AVG(f.rating), 3) AS avg_rating
FROM fact_orders f JOIN dim_dish d ON f.food_id = d.dish_id
GROUP BY d.category;

CREATE OR REPLACE VIEW vw_restaurant_quality AS
SELECT r.restaurant_name,
       ROUND(AVG(f.rating), 3) AS avg_rating,
       COUNT(f.order_id) AS orders,
       MAX(f.rating_count) AS max_reviews,
       ROUND(AVG(f.rating) * LOG10(1 + AVG(f.rating_count)), 3) AS rqi
FROM fact_orders f JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY f.restaurant_id, r.restaurant_name;

CREATE OR REPLACE VIEW vw_city_density AS
SELECT l.city, l.state,
       COUNT(f.order_id) AS total_orders,
       COUNT(DISTINCT l.location_id) AS localities,
       ROUND(COUNT(f.order_id) * 1.0 / COUNT(DISTINCT l.location_id), 1) AS order_density
FROM fact_orders f JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.city, l.state;

CREATE OR REPLACE VIEW vw_peak_days AS
SELECT d.order_date, d.day_of_week, d.month_name,
       COUNT(f.order_id) AS daily_orders,
       ROUND(SUM(f.price), 2) AS daily_revenue
FROM fact_orders f JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.order_date, d.day_of_week, d.month_name;

-- ============================================================
-- END OF SCRIPT
-- ============================================================