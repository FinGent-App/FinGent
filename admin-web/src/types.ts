export interface Citation {
  id?: string;
  title: string;
  doc_type: string;
  badge_label?: string;
  source_url?: string;
  score?: number;
  ticker?: string;
}

export interface AgentLog {
  id: string;
  user_id: string;
  prompt: string;
  selected_tools: string[];
  tool_arguments: Record<string, any>;
  tool_output?: string;
  final_answer?: string;
  citations: Citation[];
  market_type: string;
  model_name: string;
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  latency_ms: number;
  relevance_score: number;
  status: string;
  error_message?: string;
  created_at: string;
}

export interface LLMOpsAnalytics {
  total_queries: number;
  total_tokens: number;
  prompt_tokens: number;
  completion_tokens: number;
  estimated_cost_usd: number;
  estimated_cost_idr: number;
  avg_latency_ms: number;
  avg_relevance_score: number;
  tools_distribution: Record<string, number>;
  market_distribution: Record<string, number>;
}

export interface TableColumn {
  column_name: string;
  data_type: string;
  is_nullable?: string;
}

export interface TableOverview {
  table_name: string;
  row_count: number;
  columns: TableColumn[];
}

export interface TableDataResponse {
  table_name: string;
  page: number;
  limit: number;
  total_rows: number;
  total_pages: number;
  columns: TableColumn[];
  rows: Record<string, any>[];
}

export interface FeedStatus {
  name: string;
  market: string;
  category: string;
  feed_url: string;
  status: string;
  articles_in_db: number;
  latest_article_at?: string;
}
