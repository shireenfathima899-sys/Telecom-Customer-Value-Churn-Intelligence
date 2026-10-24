
-- ============================================================
-- PROJECT: Telecom Customer Value & Churn Intelligence
-- TOOL: MySQL 8.0+
-- DATASET: Telco Customer Churn
-- GRAIN: One row per customer
--

-- ============================================================


-- ============================================================
-- 1. DATABASE SETUP
-- ============================================================

CREATE DATABASE IF NOT EXISTS telco_churn_analysis;

USE telco_churn_analysis;


-- ============================================================
-- 2. RAW STAGING TABLE


-- ============================================================

CREATE TABLE IF NOT EXISTS telco_customers_raw (
    customerID       VARCHAR(50),
    gender           VARCHAR(20),
    SeniorCitizen    VARCHAR(10),
    Partner          VARCHAR(10),
    Dependents       VARCHAR(10),
    tenure           VARCHAR(20),
    PhoneService     VARCHAR(30),
    MultipleLines    VARCHAR(50),
    InternetService  VARCHAR(50),
    OnlineSecurity   VARCHAR(50),
    OnlineBackup     VARCHAR(50),
    DeviceProtection VARCHAR(50),
    TechSupport      VARCHAR(50),
    StreamingTV      VARCHAR(50),
    StreamingMovies  VARCHAR(50),
    Contract         VARCHAR(50),
    PaperlessBilling VARCHAR(20),
    PaymentMethod    VARCHAR(100),
    MonthlyCharges   VARCHAR(30),
    TotalCharges     VARCHAR(30),
    Churn            VARCHAR(10)
);


-- ============================================================
-- 3. DATA QUALITY CHECKS

-- ============================================================

-- 3.1 Total number of records
SELECT COUNT(*) AS total_records
FROM telco_customers_raw;


-- 3.2 Check duplicate customer IDs
SELECT
    customerID,
    COUNT(*) AS record_count
FROM telco_customers_raw
GROUP BY customerID
HAVING COUNT(*) > 1;


-- 3.3 Check missing or blank customer IDs
SELECT COUNT(*) AS missing_customer_ids
FROM telco_customers_raw
WHERE customerID IS NULL
   OR TRIM(customerID) = '';


-- 3.4 Check invalid churn labels
SELECT Churn, COUNT(*) AS customer_count
FROM telco_customers_raw
GROUP BY Churn;


-- 3.5 Identify blank TotalCharges
SELECT
    COUNT(*) AS blank_total_charges
FROM telco_customers_raw
WHERE TotalCharges IS NULL
   OR TRIM(TotalCharges) = '';


-- 3.6 Verify blank TotalCharges against tenure
SELECT
    tenure,
    COUNT(*) AS customer_count
FROM telco_customers_raw
WHERE TotalCharges IS NULL
   OR TRIM(TotalCharges) = ''
GROUP BY tenure;


-- 3.7 Inspect numeric fields that cannot be converted
SELECT *
FROM telco_customers_raw
WHERE (
    NULLIF(TRIM(tenure), '') IS NOT NULL
    AND TRIM(tenure) NOT REGEXP '^[0-9]+$'
)
OR (
    NULLIF(TRIM(MonthlyCharges), '') IS NOT NULL
    AND TRIM(MonthlyCharges)
        NOT REGEXP '^[0-9]+([.][0-9]+)?$'
)
OR (
    NULLIF(TRIM(TotalCharges), '') IS NOT NULL
    AND TRIM(TotalCharges)
        NOT REGEXP '^[0-9]+([.][0-9]+)?$'
);


-- ============================================================
-- 4. CLEANED ANALYTICAL VIEW
--
-- Convert numeric columns to appropriate types.
-- Convert blank TotalCharges to NULL.
-- Do not delete customers with missing TotalCharges.
-- Create a numeric churn flag.
-- ============================================================

CREATE OR REPLACE VIEW vw_telco_customers AS
SELECT
    TRIM(customerID) AS customerID,
    TRIM(gender) AS gender,

    CAST(NULLIF(TRIM(SeniorCitizen), '') AS UNSIGNED)
        AS SeniorCitizen,

    TRIM(Partner) AS Partner,
    TRIM(Dependents) AS Dependents,

    CAST(NULLIF(TRIM(tenure), '') AS UNSIGNED)
        AS tenure,

    TRIM(PhoneService) AS PhoneService,
    TRIM(MultipleLines) AS MultipleLines,
    TRIM(InternetService) AS InternetService,
    TRIM(OnlineSecurity) AS OnlineSecurity,
    TRIM(OnlineBackup) AS OnlineBackup,
    TRIM(DeviceProtection) AS DeviceProtection,
    TRIM(TechSupport) AS TechSupport,
    TRIM(StreamingTV) AS StreamingTV,
    TRIM(StreamingMovies) AS StreamingMovies,
    TRIM(Contract) AS Contract,
    TRIM(PaperlessBilling) AS PaperlessBilling,
    TRIM(PaymentMethod) AS PaymentMethod,

    CAST(NULLIF(TRIM(MonthlyCharges), '') AS DECIMAL(10,2))
        AS MonthlyCharges,

    CAST(NULLIF(TRIM(TotalCharges), '') AS DECIMAL(12,2))
        AS TotalCharges,

    TRIM(Churn) AS Churn,

    CASE
        WHEN TRIM(Churn) = 'Yes' THEN 1
        WHEN TRIM(Churn) = 'No' THEN 0
        ELSE NULL
    END AS ChurnFlag

FROM telco_customers_raw
WHERE customerID IS NOT NULL
  AND TRIM(customerID) <> '';


-- ============================================================
-- 5. CLEANED DATA VALIDATION
-- ============================================================

SELECT
    COUNT(*) AS total_customers,
    COUNT(DISTINCT customerID) AS unique_customers,
    SUM(ChurnFlag) AS churned_customers,
    SUM(CASE WHEN ChurnFlag = 0 THEN 1 ELSE 0 END)
        AS retained_customers,
    SUM(CASE WHEN TotalCharges IS NULL THEN 1 ELSE 0 END)
        AS missing_total_charges,
    ROUND(AVG(ChurnFlag) * 100, 2) AS churn_rate_pct
FROM vw_telco_customers;


-- ============================================================
-- BUSINESS QUESTION 1
-- Which contract type has the highest churn risk?
-- ============================================================

SELECT
    Contract,
    COUNT(*) AS Customers,
    SUM(ChurnFlag) AS Churned,

    ROUND(AVG(MonthlyCharges), 2)
        AS AvgMonthlyCharges,

    ROUND(AVG(ChurnFlag) * 100, 2)
        AS ChurnRate

FROM vw_telco_customers
WHERE ChurnFlag IS NOT NULL
GROUP BY Contract
ORDER BY ChurnRate DESC;


-- ============================================================
-- BUSINESS QUESTION 2
-- Are higher-value customers churning more often?
--
-- TotalCharges is a historical cumulative-charge proxy,
-- not a formal measure of customer lifetime value.
-- NTILE divides customers with valid TotalCharges into
-- four approximately equal-sized groups.
-- ============================================================

WITH customer_value AS (
    SELECT
        customerID,
        TotalCharges,
        MonthlyCharges,
        ChurnFlag,

        NTILE(4) OVER (
            ORDER BY TotalCharges
        ) AS ValueQuartile

    FROM vw_telco_customers
    WHERE TotalCharges IS NOT NULL
      AND ChurnFlag IS NOT NULL
)

SELECT
    ValueQuartile,

    COUNT(*) AS Customers,

    SUM(ChurnFlag) AS ChurnedCustomers,

    ROUND(AVG(TotalCharges), 2)
        AS AvgTotalCharges,

    ROUND(AVG(MonthlyCharges), 2)
        AS AvgMonthlyCharges,

    ROUND(AVG(ChurnFlag) * 100, 2)
        AS ChurnRatePct,

    ROUND(
        SUM(CASE
            WHEN ChurnFlag = 1 THEN MonthlyCharges
            ELSE 0
        END),
        2
    ) AS MonthlyChargesAssociatedWithChurnedCustomers

FROM customer_value
GROUP BY ValueQuartile
ORDER BY ValueQuartile DESC;


-- ============================================================
-- BUSINESS QUESTION 3
-- Which tenure groups have the highest churn rate?
-- ============================================================

WITH tenure_segments AS (
    SELECT
        customerID,
        tenure,
        ChurnFlag,

        CASE
            WHEN tenure BETWEEN 0 AND 6
                THEN '0-6 months'
            WHEN tenure BETWEEN 7 AND 12
                THEN '7-12 months'
            WHEN tenure BETWEEN 13 AND 24
                THEN '13-24 months'
            WHEN tenure BETWEEN 25 AND 48
                THEN '25-48 months'
            ELSE '49+ months'
        END AS TenureGroup

    FROM vw_telco_customers
    WHERE tenure IS NOT NULL
      AND ChurnFlag IS NOT NULL
)

SELECT
    TenureGroup,
    COUNT(*) AS Customers,
    SUM(ChurnFlag) AS ChurnedCustomers,

    ROUND(AVG(ChurnFlag) * 100, 2)
        AS ChurnRatePct

FROM tenure_segments
GROUP BY TenureGroup
ORDER BY
    MIN(tenure);


-- ============================================================
-- BUSINESS QUESTION 4
-- How do contract type and payment method relate to churn?
-- ============================================================

SELECT
    Contract,
    PaymentMethod,

    COUNT(*) AS Customers,

    SUM(ChurnFlag) AS ChurnedCustomers,

    ROUND(AVG(ChurnFlag) * 100, 2)
        AS ChurnRatePct,

    ROUND(AVG(MonthlyCharges), 2)
        AS AvgMonthlyCharges

FROM vw_telco_customers
WHERE ChurnFlag IS NOT NULL
GROUP BY
    Contract,
    PaymentMethod
ORDER BY
    ChurnRatePct DESC,
    Customers DESC;


-- ============================================================
-- BUSINESS QUESTION 5
-- Which customer groups should retention teams prioritize?
--
-- Priority is based on observed churn, segment size, and
-- monthly charges associated with churned customers.
-- This is descriptive prioritization, not a churn prediction.
-- ============================================================

WITH customer_segments AS (
    SELECT
        customerID,
        Contract,
        tenure,
        MonthlyCharges,
        ChurnFlag,

        CASE
            WHEN tenure <= 12
                THEN 'Early lifecycle'
            WHEN tenure <= 48
                THEN 'Mid lifecycle'
            ELSE 'Long-tenure'
        END AS LifecycleSegment

    FROM vw_telco_customers
    WHERE tenure IS NOT NULL
      AND ChurnFlag IS NOT NULL
)

SELECT
    Contract,
    LifecycleSegment,

    COUNT(*) AS Customers,

    SUM(ChurnFlag) AS ChurnedCustomers,

    ROUND(AVG(ChurnFlag) * 100, 2)
        AS ChurnRatePct,

    ROUND(AVG(MonthlyCharges), 2)
        AS AvgMonthlyCharges,

    ROUND(
        SUM(CASE
            WHEN ChurnFlag = 1 THEN MonthlyCharges
            ELSE 0
        END),
        2
    ) AS MonthlyChargesAssociatedWithChurnedCustomers

FROM customer_segments
GROUP BY
    Contract,
    LifecycleSegment

HAVING COUNT(*) >= 20

ORDER BY
    ChurnRatePct DESC,
    MonthlyChargesAssociatedWithChurnedCustomers DESC;


-- ============================================================
-- ADDITIONAL ANALYSIS
-- Overall churn by internet service
-- ============================================================

SELECT
    InternetService,
    COUNT(*) AS Customers,
    SUM(ChurnFlag) AS ChurnedCustomers,

    ROUND(AVG(ChurnFlag) * 100, 2)
        AS ChurnRatePct

FROM vw_telco_customers
WHERE ChurnFlag IS NOT NULL
GROUP BY InternetService
ORDER BY ChurnRatePct DESC;


-- ============================================================
-- ADDITIONAL ANALYSIS
-- Customer-level dataset for Power BI export
-- ============================================================

SELECT
    customerID,
    gender,
    SeniorCitizen,
    Partner,
    Dependents,
    tenure,
    Contract,
    PaymentMethod,
    InternetService,
    MonthlyCharges,
    TotalCharges,
    Churn,
    ChurnFlag

FROM vw_telco_customers;
