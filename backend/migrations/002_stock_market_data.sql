-- ==============================================================================
-- Migration 002: Stock Market Data & Fundamentals Snapshot Cache
-- Dedicated Table for Market-Wide Performance & Valuation Metrics
-- ==============================================================================

CREATE TABLE IF NOT EXISTS stock_market_data (
    ticker VARCHAR(20) PRIMARY KEY,              -- 'BBCA', 'TLKM', 'AAPL'
    name VARCHAR(100) NOT NULL,
    sector VARCHAR(100),
    currency VARCHAR(10) DEFAULT 'IDR',
    current_price NUMERIC(15, 2) NOT NULL,

    -- 1. Periodic Performance Returns (%)
    change_24h NUMERIC(8, 2),                   -- 24H Return (%)
    change_1w  NUMERIC(8, 2),                   -- 1W Return (%)
    change_1m  NUMERIC(8, 2),                   -- 1M Return (%)
    change_3m  NUMERIC(8, 2),                   -- 3M Return (%)
    change_ytd NUMERIC(8, 2),                   -- YTD Return (%)
    change_1y  NUMERIC(8, 2),                   -- 1Y Return (%)
    change_5y  NUMERIC(8, 2),                   -- 5Y Return (%)

    -- 2. 4 Key Fundamental Metrics
    forward_pe NUMERIC(10, 2),                  -- Forward P/E
    eps NUMERIC(15, 2),                         -- LTM EPS
    forward_eps NUMERIC(15, 2),                 -- Forward EPS Estimate
    pbv_ratio NUMERIC(10, 2),                   -- PBV Ratio
    free_cashflow NUMERIC(20, 2),               -- Free Cash Flow (null for Banks)

    -- 3. Supplementary Fundamental Metrics
    trailing_pe NUMERIC(10, 2),
    roe NUMERIC(8, 2),
    market_cap NUMERIC(20, 2),
    dividend_yield NUMERIC(8, 2),

    -- Cache Metadata
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_stock_market_updated ON stock_market_data (updated_at DESC);
