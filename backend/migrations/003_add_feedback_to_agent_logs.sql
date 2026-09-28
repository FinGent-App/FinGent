-- ==============================================================================
-- Migration 003: Add Feedback (Like / Dislike) to Agent Query Logs
-- ==============================================================================

ALTER TABLE agent_query_logs ADD COLUMN IF NOT EXISTS feedback VARCHAR(20) DEFAULT NULL;
CREATE INDEX IF NOT EXISTS idx_agent_logs_feedback ON agent_query_logs (feedback);
