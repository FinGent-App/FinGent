import type { AgentLog, LLMOpsAnalytics, TableOverview, TableDataResponse, FeedStatus } from './types';

export const API_BASE = localStorage.getItem('fingent_api_url') || 'http://localhost:8000';

export async function fetchAnalytics(): Promise<LLMOpsAnalytics> {
  const res = await fetch(`${API_BASE}/api/v1/admin/analytics`);
  if (!res.ok) throw new Error(`HTTP ${res.status}: Failed to fetch analytics`);
  return res.json();
}

export async function fetchLogs(limit = 50, offset = 0): Promise<AgentLog[]> {
  const res = await fetch(`${API_BASE}/api/v1/admin/logs?limit=${limit}&offset=${offset}`);
  if (!res.ok) throw new Error(`HTTP ${res.status}: Failed to fetch logs`);
  const data = await res.json();
  return data.logs || [];
}

export async function fetchTables(): Promise<TableOverview[]> {
  const res = await fetch(`${API_BASE}/api/v1/admin/tables`);
  if (!res.ok) throw new Error(`HTTP ${res.status}: Failed to fetch tables`);
  const data = await res.json();
  return data.tables || [];
}

export async function fetchTableData(
  tableName: string,
  page = 1,
  limit = 25,
  search?: string,
  sortBy?: string,
  sortDir = 'DESC'
): Promise<TableDataResponse> {
  let url = `${API_BASE}/api/v1/admin/tables/${encodeURIComponent(tableName)}?page=${page}&limit=${limit}&sort_dir=${sortDir}`;
  if (search && search.trim()) {
    url += `&search=${encodeURIComponent(search.trim())}`;
  }
  if (sortBy) {
    url += `&sort_by=${encodeURIComponent(sortBy)}`;
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: Failed to fetch table data`);
  return res.json();
}

export async function deleteTableRow(tableName: string, rowId: string): Promise<boolean> {
  const res = await fetch(`${API_BASE}/api/v1/admin/tables/${encodeURIComponent(tableName)}/${encodeURIComponent(rowId)}`, {
    method: 'DELETE',
  });
  return res.ok;
}

export async function fetchFeedsStatus(): Promise<FeedStatus[]> {
  const res = await fetch(`${API_BASE}/api/v1/admin/feeds/status`);
  if (!res.ok) throw new Error(`HTTP ${res.status}: Failed to fetch feeds`);
  const data = await res.json();
  return data.feeds || [];
}

export async function triggerFeedSync(): Promise<{ status: string; message: string }> {
  const res = await fetch(`${API_BASE}/api/v1/admin/feeds/sync`, { method: 'POST' });
  if (!res.ok) throw new Error(`HTTP ${res.status}: Failed to trigger sync`);
  return res.json();
}

export function connectSSE(
  onEvent: (type: string, data: any) => void,
  onStatusChange: (connected: boolean) => void
): () => void {
  const url = `${API_BASE}/api/v1/admin/events`;
  const eventSource = new EventSource(url);

  eventSource.onopen = () => {
    onStatusChange(true);
  };

  eventSource.onerror = () => {
    onStatusChange(false);
  };

  eventSource.addEventListener('connected', (e: MessageEvent) => {
    try {
      const data = JSON.parse(e.data);
      onEvent('connected', data);
    } catch {}
  });

  eventSource.addEventListener('new_query_trace', (e: MessageEvent) => {
    try {
      const data = JSON.parse(e.data);
      onEvent('new_query_trace', data);
    } catch {}
  });

  eventSource.addEventListener('rss_synced', (e: MessageEvent) => {
    try {
      const data = JSON.parse(e.data);
      onEvent('rss_synced', data);
    } catch {}
  });

  return () => {
    eventSource.close();
  };
}

import type { AppToolsResponse } from './types';
import { FALLBACK_APP_TOOLS_RESPONSE } from './toolsData';

export async function fetchAppTools(): Promise<AppToolsResponse> {
  try {
    const res = await fetch(`${API_BASE}/api/v1/admin/tools`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    return data;
  } catch (err) {
    console.warn('Falling back to built-in tools catalog:', err);
    return FALLBACK_APP_TOOLS_RESPONSE;
  }
}

