-- ==============================================================================
-- Migration 002: Agent Query Logs & Tool Decision Tracing (LLMOps Observability)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS agent_query_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(64) NOT NULL DEFAULT 'default_user',
    prompt TEXT NOT NULL,
    selected_tools VARCHAR(64)[] NOT NULL DEFAULT '{}',
    tool_arguments JSONB DEFAULT '{}'::jsonb,
    tool_output TEXT,
    final_answer TEXT,
    citations JSONB DEFAULT '[]'::jsonb,
    market_type VARCHAR(20) DEFAULT 'GLOBAL',      -- 'IDX', 'US', 'GLOBAL'
    model_name VARCHAR(100) DEFAULT 'gemini-3.6-flash',
    prompt_tokens INTEGER DEFAULT 0,
    completion_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    latency_ms INTEGER DEFAULT 0,
    relevance_score NUMERIC(5, 2) DEFAULT 0.95,   -- 0.00 to 1.00
    status VARCHAR(20) NOT NULL DEFAULT 'SUCCESS', -- 'SUCCESS', 'ERROR', 'FILTERED'
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Optimized indices for fast admin dashboard retrieval and time-series analytics
CREATE INDEX IF NOT EXISTS idx_agent_logs_created_at ON agent_query_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_logs_user_id ON agent_query_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_agent_logs_market_type ON agent_query_logs (market_type);
CREATE INDEX IF NOT EXISTS idx_agent_logs_tools ON agent_query_logs USING GIN (selected_tools);
