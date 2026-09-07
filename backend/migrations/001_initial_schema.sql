-- ==============================================================================
-- FinGent PostgreSQL Database Schema (100% Supabase Compatible)
-- Standar Industri: Raw SQL, Zero ORM Overhead, High-Performance Indexing
-- ==============================================================================

-- 1. Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. News Articles Table (RSS Grounding & Realtime Market News Feed)
CREATE TABLE IF NOT EXISTS news_articles (
    id VARCHAR(64) PRIMARY KEY,                    -- Deterministic SHA-256 Hash of URL for instant deduplication
    title TEXT NOT NULL,                           -- Clean article title
    summary TEXT,                                  -- Clean snippet/description
    url TEXT UNIQUE NOT NULL,                      -- Canonical article web link
    source VARCHAR(50) NOT NULL,                   -- e.g. 'Yahoo Finance', 'CNBC'
    author VARCHAR(100),                           -- News author / publisher
    image_url TEXT,                                -- Associated thumbnail/banner image URL
    tickers VARCHAR(20)[] NOT NULL DEFAULT '{}',   -- Extracted stock tickers (e.g. ['MU', 'NVDA', 'BBCA'])
    published_at TIMESTAMPTZ NOT NULL,             -- Original publish timestamp with timezone
    fetched_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Indices for news query optimization
CREATE INDEX IF NOT EXISTS idx_news_articles_tickers ON news_articles USING GIN (tickers);
CREATE INDEX IF NOT EXISTS idx_news_articles_published_at ON news_articles (published_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_articles_source ON news_articles (source);

-- 3. User Watchlists Table (Synchronized Favorites)
CREATE TABLE IF NOT EXISTS user_watchlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(64) NOT NULL DEFAULT 'default_user',  -- Compatible with anonymous client or Supabase Auth UUID
    ticker VARCHAR(20) NOT NULL,                          -- e.g. 'BBCA', 'MU', 'NVDA'
    notes TEXT,
    added_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_watchlist_ticker UNIQUE (user_id, ticker)
);

CREATE INDEX IF NOT EXISTS idx_watchlist_user ON user_watchlists (user_id);
CREATE INDEX IF NOT EXISTS idx_watchlist_added ON user_watchlists (added_at DESC);

-- 4. Portfolio Holdings Table (Persisted User Holdings matching Swift UserHolding)
CREATE TABLE IF NOT EXISTS portfolio_holdings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(64) NOT NULL DEFAULT 'default_user',
    ticker VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    shares INTEGER NOT NULL CHECK (shares >= 0),
    price_per_share NUMERIC(15, 2) NOT NULL,
    invested_amount NUMERIC(15, 2) NOT NULL,
    sector VARCHAR(100) DEFAULT 'Technology',
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_portfolio_holding UNIQUE (user_id, ticker)
);

CREATE INDEX IF NOT EXISTS idx_holdings_user ON portfolio_holdings (user_id);

-- 5. Portfolio Transactions Table (Trade execution history)
CREATE TABLE IF NOT EXISTS portfolio_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(64) NOT NULL DEFAULT 'default_user',
    ticker VARCHAR(20) NOT NULL,
    type VARCHAR(10) NOT NULL CHECK (type IN ('BUY', 'SELL', 'DIVIDEND')),
    shares INTEGER NOT NULL,
    price_per_share NUMERIC(15, 2) NOT NULL,
    total_amount NUMERIC(15, 2) NOT NULL,
    executed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tx_user_ticker ON portfolio_transactions (user_id, ticker);
CREATE INDEX IF NOT EXISTS idx_tx_executed ON portfolio_transactions (executed_at DESC);

-- 6. AI Chat & Grounding Audit Logs (For MCP Server & AI Observation)
CREATE TABLE IF NOT EXISTS ai_chat_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(64) NOT NULL DEFAULT 'default_user',
    user_query TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    market_bias VARCHAR(20),                       -- BULLISH, BEARISH, NEUTRAL
    confidence NUMERIC(3, 2),                      -- e.g. 0.85
    cited_article_ids VARCHAR(64)[] DEFAULT '{}',  -- Foreign SHA-256 IDs of news cited
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_chat_logs_created ON ai_chat_logs (created_at DESC);
