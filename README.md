<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:1a0000,50:cc2200,100:ff6b35&height=220&section=header&text=Swiggy%20Analytics&fontSize=50&fontColor=ffffff&fontAlignY=38&desc=Food%20Delivery%20Intelligence%20%7C%20Python%20%E2%80%A2%20MySQL%20%E2%80%A2%20Star%20Schema&descAlignY=60&descSize=16&descColor=ffd6c8&animation=fadeIn" width="100%"/>

<p>
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white"/>
  <img src="https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white"/>
  <img src="https://img.shields.io/badge/Jupyter-F37626?style=for-the-badge&logo=jupyter&logoColor=white"/>
  <img src="https://img.shields.io/badge/Star%20Schema-cc2200?style=for-the-badge&logo=databricks&logoColor=white"/>
  <img src="https://img.shields.io/badge/KPIs-10%20Advanced-ff6b35?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Views-5%20Power%20BI-F2C811?style=for-the-badge&logo=powerbi&logoColor=black"/>
</p>

<p>
  <a href="#-overview">Overview</a> •
  <a href="#-data-model">Data Model</a> •
  <a href="#-kpi-queries">KPIs</a> •
  <a href="#-power-bi-views">Views</a> •
  <a href="#-project-structure">Structure</a> •
  <a href="#-getting-started">Setup</a>
</p>

</div>

---

## 🍔 Overview

> **Decode what, where, when, and why people order on Swiggy — one query at a time.**

This project delivers an end-to-end analysis of Swiggy food delivery data using a production-grade **star schema** in MySQL, exploratory analysis in **Python (Jupyter)**, and **5 pre-built views** ready to plug into Power BI. It goes beyond basic aggregations — surfacing anomalies, composite scoring, and growth trends that drive real platform decisions.

```
Raw CSVs  →  Star Schema (MySQL)  →  10 KPI Queries  →  5 Power BI Views  →  Insights
```

### Business Questions Answered
- 🏆 Which restaurants dominate revenue, and by how much? *(Revenue Concentration)*
- 📅 How is monthly revenue trending? *(MoM Growth)*
- ⭐ Which restaurants are consistently rated below 3.5? *(Quality Risk)*
- 🚨 Where is the "high price, low rating" problem worst? *(Anomaly Detection)*
- 🗺️ Which cities have the highest order density per locality? *(Geographic Intelligence)*
- 📊 How do states rank on a combined revenue + quality score? *(Composite Scoring)*

---

## 🗄️ Data Model — Star Schema

```
                    ┌──────────────────┐
                    │    dim_date      │
                    │──────────────────│
                    │ date_id   (PK)   │
                    │ order_date       │
                    │ month / month_name│
                    │ year             │
                    │ day_of_week      │
                    │ quarter          │
                    └────────┬─────────┘
                             │
       ┌─────────────────────┼──────────────────────┐
       │                     │                      │
┌──────▼──────────┐  ┌───────▼────────┐  ┌──────────▼────────┐
│  dim_restaurant │  │  dim_location  │  │     dim_dish       │
│─────────────────│  │────────────────│  │────────────────────│
│ restaurant_id   │  │ location_id    │  │ dish_id   (PK)     │
│ restaurant_name │  │ state          │  │ category           │
└─────────────────┘  │ city           │  │ dish_name          │
                     │ location       │  └────────────────────┘
                     └────────────────┘
                             │
                    ┌────────▼─────────────────────────┐
                    │         fact_orders               │
                    │───────────────────────────────────│
                    │ order_id      (PK)                │
                    │ date_id       (FK → dim_date)     │
                    │ location_id   (FK → dim_location) │
                    │ restaurant_id (FK → dim_restaurant│
                    │ food_id       (FK → dim_dish)     │
                    │ price                             │
                    │ rating                            │
                    │ rating_count                      │
                    │ price_tier                        │
                    │ is_anomaly    ← 🚨 flagged orders │
                    │ is_zero_review← 🔇 unreviewed     │
                    └───────────────────────────────────┘
```

### Table Reference

| Table | Type | Key Fields |
|-------|------|-----------|
| `dim_date` | Dimension | date, month, year, day_of_week, quarter |
| `dim_restaurant` | Dimension | restaurant_id, restaurant_name |
| `dim_location` | Dimension | state, city, location |
| `dim_dish` | Dimension | category, dish_name |
| `fact_orders` | Fact | price, rating, rating_count, price_tier, is_anomaly |

---

## 📊 KPI Queries

> **10 production-grade SQL KPIs** — from revenue concentration to composite state scoring.

<details>
<summary><b>💰 KPI 1 — Revenue Concentration Ratio</b></summary>

> What percentage of total revenue do the top 10% of restaurants generate?

**Concepts:** `PERCENT_RANK()`, CTE, conditional aggregation

```sql
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
```

</details>

<details>
<summary><b>📅 KPI 2 — Month-over-Month Revenue Growth</b></summary>

> How is revenue trending month by month?

**Concepts:** `LAG()` window function, JOIN, time-series aggregation

```sql
SELECT d.month_name, d.year, d.month,
    COUNT(f.order_id) AS orders,
    ROUND(SUM(f.price), 2) AS monthly_revenue,
    ROUND((SUM(f.price) - LAG(SUM(f.price)) OVER (ORDER BY d.year, d.month)) /
    LAG(SUM(f.price)) OVER (ORDER BY d.year, d.month) * 100, 2) AS mom_growth_pct
FROM fact_orders f JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.year, d.month, d.month_name;
```

</details>

<details>
<summary><b>⭐ KPI 3 — Low Rating Restaurants (below 3.5)</b></summary>

> Which restaurants are consistently delivering a poor experience?

**Concepts:** `HAVING`, JOIN, quality threshold filtering

```sql
SELECT r.restaurant_name,
    ROUND(AVG(f.rating), 2) AS avg_rating,
    COUNT(*) AS total_orders
FROM fact_orders f JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY f.restaurant_id, r.restaurant_name
HAVING avg_rating < 3.5
ORDER BY avg_rating ASC;
```

</details>

<details>
<summary><b>🔇 KPI 4 — Zero-Review Restaurant Rate</b></summary>

> How many restaurants have no customer reviews at all?

**Concepts:** Subquery, conditional `SUM`, percentage calculation

</details>

<details>
<summary><b>🏅 KPI 5 — Rating Quality Index (RQI)</b></summary>

> A composite score that weighs both rating AND review volume — so a 4.8 with 3 reviews doesn't beat a 4.5 with 10,000.

**Formula:** `AVG(rating) × LOG10(1 + AVG(rating_count))`

**Concepts:** `LOG10()`, custom scoring formula, JOIN

</details>

<details>
<summary><b>🍽️ KPI 6 — Category Revenue Share</b></summary>

> Which food categories (Biryani, Pizza, Burger…) drive the most revenue and ratings?

**Concepts:** Revenue share %, subquery for total, GROUP BY category

</details>

<details>
<summary><b>🚨 KPI 7 — High Price + Low Rating Anomaly Rate</b></summary>

> What % of orders are flagged as anomalies — expensive but poorly rated?

**Concepts:** Pre-flagged `is_anomaly` column, conditional aggregation, anomaly rate %

</details>

<details>
<summary><b>🏙️ KPI 8 — City Order Density Index</b></summary>

> Which cities have the most orders per locality? Identifies high-demand micro-markets.

**Concepts:** `COUNT DISTINCT`, density calculation, multi-level `GROUP BY`

```sql
SELECT l.city, l.state,
    COUNT(f.order_id) AS total_orders,
    COUNT(DISTINCT l.location_id) AS localities,
    ROUND(COUNT(f.order_id) * 1.0 / COUNT(DISTINCT l.location_id), 1) AS order_density,
    ROUND(SUM(f.price) / COUNT(DISTINCT l.location_id), 2) AS revenue_per_locality
FROM fact_orders f JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.city, l.state ORDER BY order_density DESC;
```

</details>

<details>
<summary><b>🗺️ KPI 9 — State Revenue-Quality Composite Score</b></summary>

> Ranks every state on a blended score (60% revenue + 40% quality) and assigns a strategic quadrant.

**Quadrants:**

| Quadrant | Meaning |
|----------|---------|
| `DEFEND` | High revenue + High rating — protect market share |
| `INVEST` | Low revenue + High rating — grow here |
| `IMPROVE` | High revenue + Low rating — fix quality urgently |
| `REVIEW` | Low revenue + Low rating — reassess strategy |

**Concepts:** Multi-CTE pipeline, `MIN/MAX` normalisation, composite scoring, `CASE WHEN` quadrant logic

</details>

<details>
<summary><b>📆 KPI 10 — Peak Day Revenue Analysis</b></summary>

> Which specific dates and days of the week see the highest order volume and revenue?

**Concepts:** Daily aggregation, `ORDER BY`, percentage of total

</details>

---

## 👁️ Power BI Views

> **5 pre-built SQL views** — connect directly to Power BI without writing a single DAX measure.

| View | Powers |
|------|--------|
| `vw_monthly_revenue` | Time-series revenue & order volume chart |
| `vw_category_performance` | Category revenue share & avg rating cards |
| `vw_restaurant_quality` | Restaurant leaderboard with RQI score |
| `vw_city_density` | Geographic order density map |
| `vw_peak_days` | Daily heatmap — busiest days of the week |

---

## 📁 Project Structure

```
swiggy-analysis/
│
├── 🐍 Swiggy.ipynb                # Python EDA — cleaning, exploration, visualisation
├── 🗃️  Swiggy_Analytics.sql       # Full MySQL script — schema + KPIs + views
│
├── 📂 Dimension Tables
│   ├── dim_date.csv               # Date spine with month, year, day_of_week, quarter
│   ├── dim_restaurant.csv         # Restaurant master list
│   ├── dim_location.csv           # State → City → Location hierarchy
│   └── dim_dish.csv               # Dish name and category mapping
│
├── 📂 Fact Table
│   └── fact_orders_clean.csv      # Cleaned order transactions with anomaly flags
│
└── 📖 README.md                   # You are here
```

---

## 🚀 Getting Started

### Prerequisites
```
Python 3.8+   |   MySQL 8.0+   |   Jupyter Notebook   |   MySQL Workbench
```

### 1. Clone the repository
```bash
git clone https://github.com/chayanshh/swiggy-analysis.git
cd swiggy-analysis
```

### 2. Run the Python EDA notebook
```bash
jupyter notebook Swiggy.ipynb
```

### 3. Set up the MySQL database

Run `Swiggy_Analytics.sql` in MySQL Workbench. It executes in 5 steps:

```
STEP 1 → CREATE TABLES    (star schema with FK constraints)
STEP 2 → LOAD DATA        (update file paths to your local directory)
STEP 3 → ADD INDEXES      (7 indexes for query performance)
STEP 4 → KPI QUERIES      (10 analytical queries)
STEP 5 → CREATE VIEWS     (5 views ready for Power BI)
```

### 4. Update file paths before loading data
```sql
SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE '/your/path/dim_date_clean.csv'
INTO TABLE dim_date
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;
```
> Repeat for all 5 CSV files — update the path for each one.

### 5. Connect to Power BI
Open Power BI Desktop → **Get Data → MySQL database** → connect to `swiggy_analytics` → select the 5 `vw_*` views.

---

## 🧩 Data Pipeline

```mermaid
flowchart LR
    A[📁 5 CSVs] --> B[🐍 Python EDA\nSwiggy.ipynb]
    B --> C[🗃️ MySQL\nStar Schema]
    C --> D[🔢 10 KPI Queries]
    D --> E[👁️ 5 Power BI Views]
    E --> F[📊 Dashboard]
    F --> G[💡 Decisions]

    style A fill:#1a0000,color:#ffd6c8
    style G fill:#cc2200,color:#ffffff
```

---

## ⚡ Performance Design

This project is built with query performance in mind — **7 indexes** on the fact table cover every join and filter used in the KPI queries:

```sql
CREATE INDEX idx_fact_date     ON fact_orders(date_id);
CREATE INDEX idx_fact_location ON fact_orders(location_id);
CREATE INDEX idx_fact_rest     ON fact_orders(restaurant_id);
CREATE INDEX idx_fact_food     ON fact_orders(food_id);
CREATE INDEX idx_fact_rating   ON fact_orders(rating);
CREATE INDEX idx_fact_price    ON fact_orders(price);
CREATE INDEX idx_fact_anomaly  ON fact_orders(is_anomaly);
```

---

## 🛠️ SQL Concepts Covered

```
✅ Star Schema Design       FK constraints, surrogate keys
✅ Window Functions         PERCENT_RANK, LAG, OVER, PARTITION BY
✅ CTEs                     Multi-step WITH clause pipelines
✅ Composite Scoring        MIN/MAX normalisation, weighted scoring
✅ Anomaly Detection        Pre-flagged columns + rate calculation
✅ Data Loading             LOAD DATA LOCAL INFILE, SET GLOBAL local_infile
✅ Indexing                 7 performance indexes on fact table
✅ Views                    CREATE OR REPLACE VIEW for BI connectivity
✅ Custom Formulas          Rating Quality Index (RQI) with LOG10
✅ Strategic Quadrants      CASE WHEN multi-condition classification
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/kpi-11-cuisine-trend`
3. Add your query with a business-context comment header
4. Open a Pull Request

---

## 👤 Author

**Chayansh Jain**
- GitHub: [@chayanshh](https://github.com/chayanshh)
- LinkedIn: [linkedin.com/in/chayanshh05](https://www.linkedin.com/in/chayanshh05)

---

<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:ff6b35,50:cc2200,100:1a0000&height=120&section=footer" width="100%"/>

*Built with 🍔 Python · MySQL · Star Schema · Window Functions*

</div>
