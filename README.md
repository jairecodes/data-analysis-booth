# BUSN 32120 Final Project
## Anomalous pricing in cleaning products post-COVID

**Author:** Jaire Augusto Byers | **Course:** BUSN 32120 | **March 2026**

---

## Overview

This project tests whether household cleaning products experienced anomalous price increases relative to comparable consumer goods categories post-2019, above and beyond general macroeconomic conditions. The analysis is framed for economic consultants and legal counsel evaluating shrinkflation and margin expansion claims in consumer goods litigation.

All data are sourced from the **FRED API** (CPI, PPI, Consumer Sentiment, recession indicator). The unit of observation is a category-month panel across four categories: cleaning (treated), food, nondurables, and shelter.

---

## Methods

- **EDA:** relative price indices, markup indices (CPI/PPI), and anomalous pricing flags across categories and periods
- **SQL:** 11 queries via SQLite in Python covering GROUP BY, window functions, joins, subqueries, and CTEs
- **Regression:** two logistic regression models (sklearn, balanced class weighting) predicting anomalous pricing under post-2019 and post-COVID cutoff definitions

---

## Key Finding

Cleaning products are significantly more likely to be classified as anomalously priced post-2019 relative to control categories (interaction coefficients: 0.84 post-2019, 0.33 post-COVID). Markup is consistently positive and sentiment consistently negative across specifications, weakening cost-side and demand-pull explanations respectively.

---

## Files

| File | Description |
|------|-------------|
| `BUSN32120_FINAL_BYERS.ipynb` | Main notebook |
| `BUSN32120_FINAL_BYERS_queries.sql` | All SQL queries with comments |
| `README.md` | This file |

---

## Dependencies
`pandas`, `numpy`, `matplotlib`, `seaborn`, `plotly`, `scikit-learn`, `statsmodels`, `requests`

A valid FRED API key is required. Free keys available at [fred.stlouisfed.org](https://fred.stlouisfed.org/docs/api/api_key.html).
