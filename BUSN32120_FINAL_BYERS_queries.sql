-- ============================================================
-- BUSN 32120 Final Project — SQL Queries
-- Author: Jaire Augusto Byers
-- Description: All SQL queries used in the final project,
--              executed via SQLite in Python using pd.read_sql().
--              Two tables are queried throughout:
--                - panel: long-format category-month observations
--                - master: wide-format macro series from FRED
-- ============================================================


-- ============================================================
-- QUERY 1 | Descriptive statistics by category and period
-- ============================================================
-- What: Computes MIN, MEDIAN, skewness (Pearson's approximation),
--       AVG, and MAX of relative_price for each category-period group.
-- How:  GROUP BY category and period. MEDIAN and STDEV are custom
--       aggregate functions registered in Python via conn.create_aggregate().
--       Skewness is approximated as 3*(mean - median) / stdev.
-- Why:  Provides the core descriptive summary of relative pricing behavior
--       across categories and periods. Establishes the baseline distributional
--       differences that motivate the regression analysis.

SELECT 
    category,
    period,
    MIN(relative_price),
    MEDIAN(relative_price),
    3*(AVG(relative_price)-MEDIAN(relative_price))/STDEV(relative_price) as [skew],
    AVG(relative_price), 
    MAX(relative_price)
FROM panel
GROUP BY category, period  
ORDER BY category, period DESC;


-- ============================================================
-- QUERY 2 | Anomalous pricing flag rate by category and period
-- ============================================================
-- What: Counts the number of anomalous months and computes the
--       proportion of total months flagged as anomalous, by
--       category and period.
-- How:  SUM(anomalous) counts flagged months since the flag is
--       binary (0/1). CAST to FLOAT avoids integer division.
--       GROUP BY category and period.
-- Why:  Directly quantifies how frequently each category enters
--       anomalous pricing territory across periods. A large jump
--       in the anomalous proportion for cleaning post-2019,
--       relative to control categories, is the central descriptive
--       finding motivating the logistic regression.

SELECT 
    category, 
    period, 
    SUM(anomalous) as [# anomalous mos.],
    CAST(SUM(anomalous) AS FLOAT)/COUNT(*) as [proportion]
FROM panel
GROUP BY category, period
ORDER BY category, period DESC;


-- ============================================================
-- QUERY 3 | Consumer sentiment by anomalous vs. normal months
-- ============================================================
-- What: Computes average consumer sentiment separately for months
--       flagged as anomalously priced and months not flagged.
-- How:  GROUP BY the binary anomalous flag. AVG(sentiment) is
--       pulled directly from panel, where sentiment is a
--       category-invariant macro control merged in from FRED.
-- Why:  Tests the demand-pull hypothesis. If sentiment is lower
--       during anomalous pricing months, consumers were not driving
--       price increases through increased willingness to pay —
--       weakening a demand-side defense and strengthening the
--       inference that price increases reflect producer conduct.

SELECT 
    anomalous as [pricing], 
    AVG(sentiment)
FROM panel
GROUP BY anomalous;


-- ============================================================
-- QUERY 4 | Consumer sentiment above vs. below pre-2019 mean
--           (JOIN + SUBQUERY)
-- ============================================================
-- What: For cleaning products only, splits observations into two
--       regimes — above and below the pre-2019 average relative
--       price — and computes average consumer sentiment in each.
-- How:  CASE WHEN with a correlated subquery computing the pre-2019
--       average relative price for cleaning. Joins panel to master
--       on date to retrieve sentiment from the wide-format table.
-- Why:  Provides a more targeted version of Query 3, focused on
--       the treated category only. The sentiment contrast between
--       price regimes directly informs the demand-pull vs. market
--       power interpretation in the writeup.

SELECT
    CASE 
        WHEN p.relative_price > (
            SELECT AVG(relative_price) 
            FROM panel 
            WHERE category = 'cleaning' AND post_2019 = 0
        ) THEN 'above pre-2019 mean'
        ELSE 'below pre-2019 mean'
    END AS price_regime,
    AVG(m.sentiment) as [AVG(sentiment)]
FROM panel p
JOIN master m ON p.date = m.date
WHERE p.category = 'cleaning'
GROUP BY price_regime;


-- ============================================================
-- QUERY 5 | Treatment label join
--           (JOIN)
-- ============================================================
-- What: Joins panel to the treatment lookup table to attach
--       human-readable treatment labels ('treated', 'control')
--       to each panel observation.
-- How:  LEFT JOIN on category. The treatment table is a small
--       manually constructed dataframe loaded into SQLite with
--       two columns: category and treatment_label.
-- Why:  Produces a labeled dataset for downstream grouped summaries
--       and readable output tables. Separates the treatment
--       classification logic from the main panel construction.

SELECT 
    p.*, 
    t.treatment_label
FROM panel p
LEFT JOIN treatment t
    ON p.category = t.category;


-- ============================================================
-- QUERY 6 | Relative CPI vs. relative PPI for cleaning by period
--           (JOIN)
-- ============================================================
-- What: Computes the average relative CPI (from panel) and average
--       relative PPI (ppi_cleaning / ppi_nondurable * 100, computed
--       inline from master) for cleaning products by period.
-- How:  JOIN panel to master on date, filter to cleaning category,
--       GROUP BY period. The relative PPI is computed inline as
--       ppi_cleaning divided by ppi_nondurable, scaled to index form.
-- Why:  Directly quantifies the consumer-producer price wedge across
--       periods. A widening gap between relative CPI and relative PPI
--       over time is evidence of margin expansion — producers capturing
--       more consumer surplus beyond input cost pass-through.

SELECT 
    p.period,
    AVG(p.relative_price)                        as [AVG(rel_cpi)],
    AVG(m.ppi_cleaning / m.ppi_nondurable * 100) as [AVG(rel_ppi)]
FROM panel p
JOIN master m ON p.date = m.date
WHERE p.category = 'cleaning'
GROUP BY p.period
ORDER BY p.period DESC;


-- ============================================================
-- QUERY 7 | Categories with above-grand-mean relative prices
--           (GROUP BY + HAVING with subquery)
-- ============================================================
-- What: Returns category-period groups whose average relative price
--       exceeds the grand mean across all observations.
-- How:  GROUP BY category and period, with a HAVING clause filtering
--       on a subquery that computes the overall average relative price.
--       HAVING is required here rather than WHERE because the filter
--       operates on an aggregated value.
-- Why:  Identifies which category-period combinations are persistently
--       above-average in relative pricing. Cleaning post-2019 is
--       expected to appear here while control categories do not,
--       providing a simple SQL-level confirmation of the main finding.

SELECT 
    category, 
    period, 
    AVG(relative_price)
FROM panel
GROUP BY category, period
HAVING 
    AVG(relative_price) >
        (SELECT AVG(relative_price) FROM panel)
ORDER BY category, period DESC;


-- ============================================================
-- QUERY 8 | Month-over-month change in relative price
--           (WINDOW FUNCTION — LAG)
-- ============================================================
-- What: Computes the month-over-month change in relative_price
--       for each category by subtracting the prior month's value
--       from the current month's value.
-- How:  LAG(relative_price, 1) retrieves the previous row's value
--       within each category partition, ordered by date. The
--       difference is the MoM change. Results are filtered to
--       the cleaning category and the top 20 largest increases
--       are returned.
-- Why:  Identifies the specific months in which cleaning product
--       relative prices accelerated most sharply. These months
--       can be cited in the writeup to anchor the timing of the
--       pricing anomaly to specific economic events.

SELECT
    date,
    category,
    relative_price,
    relative_price - LAG(relative_price, 1) OVER (
        PARTITION BY category ORDER BY date
    ) as mom_change
FROM panel;


-- ============================================================
-- QUERY 9 | 12-month rolling average relative price by category
--           (WINDOW FUNCTION — AVG OVER PARTITION)
-- ============================================================
-- What: Computes a 12-month rolling average of relative_price
--       for each category.
-- How:  AVG() OVER with ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
--       defines a 12-row (12-month) rolling window within each
--       category partition, ordered by date.
-- Why:  Smooths month-to-month noise in the relative price series
--       to make the long-run divergence trend more visible. The
--       rolling average is plotted in Chart V alongside the raw
--       monthly series, with 2019 and 2022 cutoffs marked, to
--       provide a clean visual of the structural break.

SELECT
    date,
    category,
    relative_price,
    AVG(relative_price) OVER (
        PARTITION BY category 
        ORDER BY date 
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) as rolling_avg_12m
FROM panel
ORDER BY category, date;


-- ============================================================
-- QUERY 10 | Top 15 months — cleaning vs. food price gap
--            (JOIN with subqueries)
-- ============================================================
-- What: For each date, computes the difference between cleaning
--       and food relative prices, returning the 15 months with
--       the largest gap.
-- How:  Two subqueries in the FROM clause each filter panel to
--       one category, producing single-category date-price tables.
--       These are joined on date and the gap is computed as
--       cleaning minus food relative price.
-- Why:  Identifies the specific months where the cleaning-food
--       pricing divergence was most extreme. Food is the most
--       natural comparator since both are consumer staples with
--       similar demand inelasticity. The top gap months are
--       cited in the writeup to anchor the anomaly to specific
--       periods.

SELECT
    c.date,
    c.relative_price                    as cleaning_price,
    f.relative_price                    as food_price,
    c.relative_price - f.relative_price as price_gap
FROM 
    (SELECT date, relative_price FROM panel WHERE category = 'cleaning') c
JOIN 
    (SELECT date, relative_price FROM panel WHERE category = 'food') f
ON c.date = f.date
ORDER BY price_gap DESC
LIMIT 15;


-- ============================================================
-- QUERY 11 | Average relative price during recession vs. 
--            non-recession months by category (CTE)
-- ============================================================
-- What: Computes average relative price by category and recession
--       status, using a CTE to first build the grouped aggregation
--       before filtering in the outer query.
-- How:  The CTE recession_avg groups panel by category and recession
--       flag and computes AVG(relative_price). The outer query then
--       filters to the relevant categories.
-- Why:  Tests whether recession periods explain the cleaning price
--       anomaly. If cleaning prices are anomalously high outside
--       recession periods as well, the recession defense is weakened.
--       This result is cited in the writeup to address the
--       macroeconomic conditions alternative explanation.

WITH recession_avg as (
    SELECT
        category,
        recession,
        AVG(relative_price) as avg_relative_price
    FROM panel
    GROUP BY category, recession
)
SELECT
    category,
    recession,
    avg_relative_price
FROM recession_avg
WHERE category IN ('cleaning', 'food', 'nondurable')
ORDER BY category, recession;