import type { AgentLog, LLMOpsAnalytics, TableOverview, TableDataResponse, FeedStatus } from './types';

export const API_BASE = import.meta.env.VITE_API_URL || localStorage.getItem('fingent_api_url') || 'https://fingent-backend-238432086960.asia-southeast2.run.app';

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

  eventSource.addEventListener('trace_feedback_updated', (e: MessageEvent) => {
    try {
      const data = JSON.parse(e.data);
      onEvent('trace_feedback_updated', data);
    } catch {}
  });

  return () => {
    eventSource.close();
  };
}

import type { AppToolsResponse, AppTool } from './types';
import { FALLBACK_APP_TOOLS_RESPONSE, FALLBACK_APP_TOOLS } from './toolsData';

export async function fetchAppTools(): Promise<AppToolsResponse> {
  try {
    const res = await fetch(`${API_BASE}/api/v1/admin/tools`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    const remoteTools: AppTool[] = data.tools || [];
    const remoteToolMap = new Map<string, AppTool>();
    remoteTools.forEach(t => {
      if (t.name) remoteToolMap.set(t.name.toLowerCase(), t);
      if (t.id) remoteToolMap.set(t.id.toLowerCase(), t);
    });

    const mergedTools: AppTool[] = [];
    const seen = new Set<string>();

    // Baseline order from FALLBACK_APP_TOOLS (preserves on-device group order, including localAIExplanation)
    for (const fb of FALLBACK_APP_TOOLS) {
      const match = remoteToolMap.get(fb.name.toLowerCase()) || (fb.id ? remoteToolMap.get(fb.id.toLowerCase()) : undefined);
      if (match) {
        mergedTools.push({
          ...fb,
          ...match,
          display_name: match.display_name || fb.display_name,
        });
        seen.add(fb.name.toLowerCase());
        if (match.name) seen.add(match.name.toLowerCase());
      } else {
        mergedTools.push(fb);
        seen.add(fb.name.toLowerCase());
      }
    }

    // Add any additional tools returned by remote that weren't in FALLBACK_APP_TOOLS
    for (const rt of remoteTools) {
      if (rt.name && !seen.has(rt.name.toLowerCase())) {
        mergedTools.push(rt);
        seen.add(rt.name.toLowerCase());
      }
    }

    const onDeviceCount = mergedTools.filter(t => t.tier === 'on_device').length;
    const cloudAgentCount = mergedTools.filter(t => t.tier === 'cloud_agent').length;
    const mcpServerCount = mergedTools.filter(t => t.tier === 'mcp_server').length;

    return {
      count: mergedTools.length,
      tier_breakdown: {
        on_device: onDeviceCount,
        cloud_agent: cloudAgentCount,
        mcp_server: mcpServerCount,
      },
      tools: mergedTools,
    };
  } catch (err) {
    console.warn('Falling back to built-in tools catalog:', err);
    return FALLBACK_APP_TOOLS_RESPONSE;
  }
}


