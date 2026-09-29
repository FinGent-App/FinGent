import React, { useState } from 'react';
import type { AgentLog, LLMOpsAnalytics } from '../types';
import { 
  Zap, 
  Coins, 
  Clock, 
  CheckCircle2, 
  Flame, 
  Wrench, 
  Globe2, 
  ChevronDown, 
  ChevronRight, 
  ExternalLink,
  Bot,
  ThumbsUp,
  ThumbsDown
} from 'lucide-react';

interface LLMOpsViewProps {
  analytics: LLMOpsAnalytics | null;
  logs: AgentLog[];
}

export const LLMOpsView: React.FC<LLMOpsViewProps> = ({ analytics, logs }) => {
  const [expandedLogId, setExpandedLogId] = useState<string | null>(null);

  const toggleExpand = (id: string) => {
    setExpandedLogId(prev => (prev === id ? null : id));
  };

  const totalToolCalls = analytics?.tools_distribution 
    ? Object.values(analytics.tools_distribution).reduce((a, b) => a + b, 0)
    : 1;

  const formatLatencySec = (ms: number): string => {
    const sec = (ms || 0) / 1000;
    return `${sec.toFixed(2).replace('.', ',')} s`;
  };

  return (
    <div id="llmops-view">
      {/* 1. Top Metrics Row */}
      <div className="stats-grid" id="stats-grid">
        <div className="stat-card" style={{ '--accent-color': 'var(--accent-cyan)' } as any}>
          <div className="stat-header">
            <span className="stat-title">Total Agent Queries</span>
            <Zap className="stat-icon" size={18} />
          </div>
          <div className="stat-value">{analytics?.total_queries.toLocaleString() || '0'}</div>
          <div className="stat-subtext">Live prompts processed via iOS & Web</div>
        </div>

        <div className="stat-card" style={{ '--accent-color': 'var(--accent-amber)' } as any}>
          <div className="stat-header">
            <span className="stat-title">Gemini Token Usage</span>
            <Flame className="stat-icon" size={18} />
          </div>
          <div className="stat-value">{(analytics?.total_tokens || 0).toLocaleString()}</div>
          <div className="stat-subtext">
            Prompt: {(analytics?.prompt_tokens || 0).toLocaleString()} | Comp: {(analytics?.completion_tokens || 0).toLocaleString()}
          </div>
        </div>

        <div className="stat-card" style={{ '--accent-color': 'var(--accent-emerald)' } as any}>
          <div className="stat-header">
            <span className="stat-title">Estimated Cost</span>
            <Coins className="stat-icon" size={18} />
          </div>
          <div className="stat-value">${analytics?.estimated_cost_usd.toFixed(4) || '0.0000'}</div>
          <div className="stat-subtext">≈ Rp {(analytics?.estimated_cost_idr || 0).toLocaleString()}</div>
        </div>

        <div className="stat-card" style={{ '--accent-color': 'var(--accent-blue)' } as any}>
          <div className="stat-header">
            <span className="stat-title">Average Latency</span>
            <Clock className="stat-icon" size={18} />
          </div>
          <div className="stat-value">{formatLatencySec(analytics?.avg_latency_ms || 0)}</div>
          <div className="stat-subtext">E2E Reasoning & Grounding time</div>
        </div>

        <div className="stat-card" style={{ '--accent-color': 'var(--accent-purple)' } as any}>
          <div className="stat-header">
            <span className="stat-title">Relevance & Faithfulness</span>
            <CheckCircle2 className="stat-icon" size={18} />
          </div>
          <div className="stat-value">{Math.round((analytics?.avg_relevance_score || 0.95) * 100)}%</div>
          <div className="stat-subtext">Zero hallucination threshold</div>
        </div>
      </div>

      {/* 2. Middle Row: Tool Breakdown & Market Ratio */}
      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: '1.25rem', marginBottom: '2rem' }}>
        <div className="glass-panel">
          <div className="panel-header">
            <div className="panel-title">
              <Wrench size={18} color="var(--accent-cyan)" />
              <span>Agent Tool Calling Distribution</span>
            </div>
            <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Top Executed Tools</span>
          </div>

          <div>
            {analytics?.tools_distribution && Object.entries(analytics.tools_distribution).length > 0 ? (
              Object.entries(analytics.tools_distribution).map(([tool, count], idx) => {
                const pct = Math.round((count / Math.max(1, totalToolCalls)) * 100);
                const colors = ['#00d2ff', '#a855f7', '#10b981', '#f59e0b', '#38bdf8'];
                const color = colors[idx % colors.length];
                return (
                  <div key={tool} className="dist-item">
                    <div className="dist-labels">
                      <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--text-primary)' }}>{tool}</span>
                      <span style={{ color: 'var(--text-secondary)' }}>{count} calls ({pct}%)</span>
                    </div>
                    <div className="dist-track">
                      <div className="dist-fill" style={{ width: `${pct}%`, background: color }} />
                    </div>
                  </div>
                );
              })
            ) : (
              <div style={{ color: 'var(--text-muted)', fontSize: '0.875rem', padding: '1rem 0' }}>
                Menunggu pemanggilan tool pertama dari user...
              </div>
            )}
          </div>
        </div>

        <div className="glass-panel">
          <div className="panel-header">
            <div className="panel-title">
              <Globe2 size={18} color="var(--accent-purple)" />
              <span>Market Routing Split</span>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', marginTop: '0.5rem' }}>
            <div>
              <div className="dist-labels">
                <span style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', color: 'var(--text-primary)' }}>
                  <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#ef4444', display: 'inline-block' }} />
                  IDX / Indonesia Stocks
                </span>
                <span style={{ color: 'var(--text-secondary)' }}>
                  {analytics?.market_distribution?.IDX || 0} queries
                </span>
              </div>
              <div className="dist-track">
                <div 
                  className="dist-fill" 
                  style={{ 
                    width: `${Math.round(((analytics?.market_distribution?.IDX || 0) / Math.max(1, (analytics?.total_queries || 1))) * 100)}%`, 
                    background: '#ef4444' 
                  }} 
                />
              </div>
            </div>

            <div>
              <div className="dist-labels">
                <span style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', color: 'var(--text-primary)' }}>
                  <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#38bdf8', display: 'inline-block' }} />
                  US / Global Equities
                </span>
                <span style={{ color: 'var(--text-secondary)' }}>
                  {analytics?.market_distribution?.US || 0} queries
                </span>
              </div>
              <div className="dist-track">
                <div 
                  className="dist-fill" 
                  style={{ 
                    width: `${Math.round(((analytics?.market_distribution?.US || 0) / Math.max(1, (analytics?.total_queries || 1))) * 100)}%`, 
                    background: '#38bdf8' 
                  }} 
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 3. Live Agent Decision Flow & Trace Stream */}
      <div className="glass-panel">
        <div className="panel-header">
          <div className="panel-title">
            <Bot size={20} color="var(--accent-cyan)" />
            <span>Live Agent Decision Trace (User Request ➔ LLM Reasoning ➔ Tool ➔ Answer)</span>
          </div>
          <span style={{ fontSize: '0.8rem', color: 'var(--accent-emerald)', fontFamily: 'var(--font-mono)' }}>
            ● Auto-Streaming via SSE
          </span>
        </div>

        {logs.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '3rem 1rem', color: 'var(--text-muted)' }}>
            <div style={{ fontSize: '2.5rem', marginBottom: '0.5rem' }}>🤖</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)', marginBottom: '0.25rem' }}>Belum ada riwayat percakapan</div>
            <div style={{ fontSize: '0.85rem' }}>
              Ajukan pertanyaan di aplikasi iPhone Anda (misal: "Kenapa saham BBCA turun?") untuk melihat alur eksekusi tool di sini secara live!
            </div>
          </div>
        ) : (
          <div className="trace-feed">
            {logs.map(log => {
              const isExpanded = expandedLogId === log.id;
              const hasTools = log.selected_tools && log.selected_tools.length > 0;
              const isIDX = log.market_type === 'IDX';

              return (
                <div key={log.id} className="trace-card">
                  <div className="trace-top">
                    <div className="trace-badges">
                      <span className={`badge ${isIDX ? 'badge-idx' : 'badge-us'}`}>
                        {isIDX ? '🇮🇩 IDX' : '🇺🇸 US / GLOBAL'}
                      </span>
                      {hasTools ? (
                        log.selected_tools.map(t => (
                          <span key={t} className="badge badge-tool">
                            🛠️ {t}
                          </span>
                        ))
                      ) : (
                        <span className="badge badge-tool">🧠 Direct LLM Synthesis</span>
                      )}
                      <span className="badge badge-tokens">
                        {log.total_tokens || (log.prompt_tokens + log.completion_tokens)} Tok ({formatLatencySec(log.latency_ms)})
                      </span>
                    </div>

                    <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
                      {log.created_at ? new Date(log.created_at).toLocaleTimeString() : 'Baru saja'}
                    </div>
                  </div>

                  <div className="trace-prompt">
                    💬 "{log.prompt}"
                  </div>

                  {/* Decision Tree / Tool Flow Block */}
                  {hasTools && (
                    <div className="decision-flow-box">
                      <div className="decision-flow-title">
                        <Wrench size={14} />
                        <span>LLM Selected Tool Execution:</span>
                      </div>
                      <div className="decision-flow-content">
                        Tool <strong>{log.selected_tools.join(', ')}</strong> dipanggil dengan argumen:
                        <br />
                        <div className="decision-args-code">
                          {JSON.stringify(log.tool_arguments)}
                        </div>
                      </div>

                      {log.tool_output && (
                        <div style={{ marginTop: '0.4rem', fontSize: '0.785rem', color: '#94a3b8' }}>
                          <strong>Output Context:</strong> {log.tool_output}
                        </div>
                      )}
                    </div>
                  )}

                  {/* Citations Grounding Badges */}
                  {log.citations && log.citations.length > 0 && (
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.4rem', margin: '0.6rem 0' }}>
                      <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', alignSelf: 'center' }}>
                        Grounded by:
                      </span>
                      {log.citations.map((c, i) => {
                        const hasValidLink = c.source_url && (c.source_url.startsWith('http://') || c.source_url.startsWith('https://')) && !c.source_url.includes('localhost:5173');
                        return hasValidLink ? (
                          <a 
                            key={i} 
                            href={c.source_url} 
                            target="_blank" 
                            rel="noreferrer"
                            style={{
                              fontSize: '0.725rem',
                              textDecoration: 'none',
                              background: 'rgba(255, 255, 255, 0.05)',
                              color: '#38bdf8',
                              padding: '0.2rem 0.5rem',
                              borderRadius: '4px',
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '0.25rem',
                              border: '1px solid rgba(56, 189, 248, 0.2)'
                            }}
                          >
                            <span>{c.badge_label || c.title}</span>
                            <ExternalLink size={10} />
                          </a>
                        ) : (
                          <span 
                            key={i}
                            style={{
                              fontSize: '0.725rem',
                              background: 'rgba(255, 255, 255, 0.05)',
                              color: '#94a3b8',
                              padding: '0.2rem 0.5rem',
                              borderRadius: '4px',
                              display: 'inline-flex',
                              alignItems: 'center',
                              border: '1px solid rgba(148, 163, 184, 0.2)'
                            }}
                          >
                            <span>{c.badge_label || c.title}</span>
                          </span>
                        );
                      })}
                    </div>
                  )}

                  {/* Final Response Toggle */}
                  <div style={{ marginTop: '0.75rem' }}>
                    <button
                      onClick={() => toggleExpand(log.id)}
                      style={{
                        background: 'transparent',
                        border: 'none',
                        color: 'var(--accent-cyan)',
                        fontSize: '0.8rem',
                        fontWeight: 600,
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.25rem'
                      }}
                    >
                      {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                      <span>{isExpanded ? 'Sembunyikan Jawaban AI' : 'Lihat Jawaban AI yang Diberikan'}</span>
                    </button>

                    {isExpanded && log.final_answer && (
                      <div className="final-answer-box" style={{ marginTop: '0.5rem' }}>
                        {log.final_answer}
                      </div>
                    )}

                    {/* User Feedback (Like / Dislike) Indicator */}
                    <div 
                      className="trace-feedback-container"
                      style={{
                        marginTop: '0.75rem',
                        paddingTop: '0.65rem',
                        borderTop: '1px dashed rgba(255, 255, 255, 0.08)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        flexWrap: 'wrap',
                        gap: '0.5rem'
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.785rem' }}>
                        <span style={{ color: 'var(--text-muted)', fontWeight: 500 }}>Feedback Respon:</span>
                        {log.feedback === 'like' ? (
                          <span 
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '0.35rem',
                              padding: '0.2rem 0.65rem',
                              borderRadius: '999px',
                              background: 'rgba(16, 185, 129, 0.14)',
                              color: 'var(--accent-emerald, #10b981)',
                              border: '1px solid rgba(16, 185, 129, 0.35)',
                              fontWeight: 600,
                              fontSize: '0.75rem'
                            }}
                          >
                            <ThumbsUp size={12} />
                            <span>Disukai Pengguna (Helpful)</span>
                          </span>
                        ) : log.feedback === 'dislike' ? (
                          <span 
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '0.35rem',
                              padding: '0.2rem 0.65rem',
                              borderRadius: '999px',
                              background: 'rgba(239, 68, 68, 0.14)',
                              color: '#f87171',
                              border: '1px solid rgba(239, 68, 68, 0.35)',
                              fontWeight: 600,
                              fontSize: '0.75rem'
                            }}
                          >
                            <ThumbsDown size={12} />
                            <span>Tidak Disukai (Unhelpful)</span>
                          </span>
                        ) : (
                          <span 
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '0.35rem',
                              padding: '0.2rem 0.55rem',
                              borderRadius: '999px',
                              background: 'rgba(255, 255, 255, 0.04)',
                              color: 'var(--text-muted)',
                              fontSize: '0.725rem',
                              fontStyle: 'normal'
                            }}
                          >
                            <span style={{ opacity: 0.6 }}>Belum ada rating</span>
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
