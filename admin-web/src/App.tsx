import { useState, useEffect } from 'react';
import type { AgentLog, LLMOpsAnalytics } from './types';
import { fetchAnalytics, fetchLogs, connectSSE } from './api';
import { Navbar } from './components/Navbar';
import { LLMOpsView } from './components/LLMOpsView';
import { TableExplorerView } from './components/TableExplorerView';
import { RSSFeedsView } from './components/RSSFeedsView';
import { AppToolsView } from './components/AppToolsView';

export function App() {
  const [activeTab, setActiveTab] = useState<'tools' | 'llmops' | 'tables' | 'feeds'>('tools');
  const [analytics, setAnalytics] = useState<LLMOpsAnalytics | null>(null);
  const [logs, setLogs] = useState<AgentLog[]>([]);
  const [sseConnected, setSseConnected] = useState<boolean>(false);

  const loadInitialData = async () => {
    try {
      const [analyticsData, logsData] = await Promise.all([
        fetchAnalytics(),
        fetchLogs(50, 0)
      ]);
      setAnalytics(analyticsData);
      setLogs(logsData);
    } catch (e) {
      console.warn('Backend offline or initializing:', e);
    }
  };

  useEffect(() => {
    loadInitialData();

    // Connect to real-time Server-Sent Events (SSE)
    const cleanupSSE = connectSSE(
      (eventType, data) => {
        if (eventType === 'new_query_trace' && data) {
          setLogs(prev => [data, ...prev.slice(0, 99)]);
          // Refresh analytics
          fetchAnalytics().then(setAnalytics).catch(() => {});
        } else if (eventType === 'trace_feedback_updated' && data) {
          setLogs(prev => prev.map(log => {
            const matchesId = data.id && (log.id === data.id || log.id === String(data.id));
            const matchesPrompt = data.prompt && log.prompt === data.prompt;
            if (matchesId || matchesPrompt) {
              return { ...log, feedback: data.feedback };
            }
            return log;
          }));
        }
      },
      connected => {
        setSseConnected(connected);
      }
    );

    return () => {
      cleanupSSE();
    };
  }, []);

  return (
    <div className="app-container" id="admin-app">
      <Navbar 
        activeTab={activeTab} 
        setActiveTab={setActiveTab} 
        sseConnected={sseConnected} 
      />

      <main className="main-content">
        {activeTab === 'tools' && (
          <AppToolsView />
        )}

        {activeTab === 'llmops' && (
          <LLMOpsView analytics={analytics} logs={logs} />
        )}

        {activeTab === 'tables' && (
          <TableExplorerView />
        )}

        {activeTab === 'feeds' && (
          <RSSFeedsView />
        )}
      </main>
    </div>
  );
}

export default App;
