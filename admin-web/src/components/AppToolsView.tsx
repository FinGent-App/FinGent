import React, { useState, useEffect, useMemo } from 'react';
import type { AppTool, ToolTier } from '../types';
import { fetchAppTools } from '../api';
import { 
  Wrench, 
  Search, 
  Cpu, 
  Cloud, 
  Globe, 
  ShieldCheck, 
  Clock, 
  Copy, 
  Check, 
  Terminal, 
  Database,
  ArrowRight,
  Filter,
  Sparkles,
  Layers
} from 'lucide-react';

export const AppToolsView: React.FC = () => {
  const [tools, setTools] = useState<AppTool[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [selectedTier, setSelectedTier] = useState<ToolTier | 'all'>('all');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [copiedPrompt, setCopiedPrompt] = useState<string | null>(null);
  const [selectedToolForInspect, setSelectedToolForInspect] = useState<AppTool | null>(null);

  useEffect(() => {
    fetchAppTools()
      .then(res => {
        setTools(res.tools);
        setLoading(false);
      })
      .catch(() => {
        setLoading(false);
      });
  }, []);

  const categories = useMemo(() => {
    const set = new Set<string>();
    tools.forEach(t => set.add(t.category));
    return ['all', ...Array.from(set)];
  }, [tools]);

  const filteredTools = useMemo(() => {
    return tools.filter(tool => {
      const matchesTier = selectedTier === 'all' || tool.tier === selectedTier;
      const matchesCat = selectedCategory === 'all' || tool.category === selectedCategory;
      const q = searchQuery.toLowerCase().trim();
      const matchesSearch = !q || 
        tool.name.toLowerCase().includes(q) ||
        tool.display_name.toLowerCase().includes(q) ||
        tool.description.toLowerCase().includes(q) ||
        tool.category.toLowerCase().includes(q) ||
        tool.example_queries.some(ex => ex.toLowerCase().includes(q)) ||
        tool.parameters.some(p => p.name.toLowerCase().includes(q));

      return matchesTier && matchesCat && matchesSearch;
    });
  }, [tools, selectedTier, selectedCategory, searchQuery]);

  const tierCounts = useMemo(() => {
    return {
      total: tools.length,
      on_device: tools.filter(t => t.tier === 'on_device').length,
      cloud_agent: tools.filter(t => t.tier === 'cloud_agent').length,
      mcp_server: tools.filter(t => t.tier === 'mcp_server').length,
    };
  }, [tools]);

  const handleCopyPrompt = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedPrompt(text);
    setTimeout(() => setCopiedPrompt(null), 2000);
  };

  const getTierBadge = (tier: ToolTier) => {
    switch (tier) {
      case 'on_device':
        return {
          label: 'ON-DEVICE NATIVE',
          icon: <Cpu size={12} />,
          color: 'var(--accent-cyan)',
          bg: 'rgba(0, 210, 255, 0.12)',
          border: 'rgba(0, 210, 255, 0.3)'
        };
      case 'cloud_agent':
        return {
          label: 'CLOUD RESEARCH AGENT',
          icon: <Cloud size={12} />,
          color: 'var(--accent-purple)',
          bg: 'rgba(168, 85, 247, 0.12)',
          border: 'rgba(168, 85, 247, 0.3)'
        };
      case 'mcp_server':
        return {
          label: 'MCP JSON-RPC 2.0',
          icon: <Globe size={12} />,
          color: 'var(--accent-amber)',
          bg: 'rgba(245, 158, 11, 0.12)',
          border: 'rgba(245, 158, 11, 0.3)'
        };
    }
  };

  return (
    <div id="app-tools-view" className="tools-container" style={{ animation: 'fadeIn 0.3s ease-out' }}>
      {/* 1. Header Banner */}
      <div className="tools-header-banner">
        <div className="header-left">
          <div className="tools-icon-wrapper">
            <Wrench size={26} color="var(--accent-cyan)" />
          </div>
          <div>
            <h1 className="tools-page-title">App Tools & Capabilities Directory</h1>
            <p className="tools-page-subtitle">
              Daftar resmi seluruh tool yang disediakan di aplikasi FinGent. Terdiri dari eksekusi <strong>Local On-Device</strong> (Apple Intelligence), <strong>Cloud Research Agent</strong> (Gemini 3.6 Flash + Milvus RAG), dan <strong>MCP Remote Protocol</strong>.
            </p>
          </div>
        </div>

        <div className="tools-stat-badges">
          <div className="tool-metric-card" style={{ borderColor: 'rgba(0, 210, 255, 0.3)' }}>
            <span className="metric-label">Total Tools</span>
            <span className="metric-num" style={{ color: 'var(--accent-cyan)' }}>{tierCounts.total}</span>
          </div>
          <div className="tool-metric-card" style={{ borderColor: 'rgba(16, 185, 129, 0.3)' }}>
            <span className="metric-label">On-Device (0ms)</span>
            <span className="metric-num" style={{ color: 'var(--accent-emerald)' }}>{tierCounts.on_device}</span>
          </div>
          <div className="tool-metric-card" style={{ borderColor: 'rgba(168, 85, 247, 0.3)' }}>
            <span className="metric-label">Cloud RAG</span>
            <span className="metric-num" style={{ color: 'var(--accent-purple)' }}>{tierCounts.cloud_agent}</span>
          </div>
          <div className="tool-metric-card" style={{ borderColor: 'rgba(245, 158, 11, 0.3)' }}>
            <span className="metric-label">MCP Protocol</span>
            <span className="metric-num" style={{ color: 'var(--accent-amber)' }}>{tierCounts.mcp_server}</span>
          </div>
        </div>
      </div>

      {/* 2. Filter & Search Controls */}
      <div className="tools-control-bar glass-panel">
        <div className="search-input-wrapper">
          <Search size={18} className="search-icon" />
          <input
            id="tools-search-input"
            type="text"
            placeholder="Cari nama tool, fungsi, parameter, atau kata kunci prompt..."
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            className="search-field"
          />
          {searchQuery && (
            <button 
              className="clear-search-btn"
              onClick={() => setSearchQuery('')}
            >
              ✕
            </button>
          )}
        </div>

        <div className="tier-filter-pills">
          <button
            className={`filter-pill ${selectedTier === 'all' ? 'active' : ''}`}
            onClick={() => setSelectedTier('all')}
          >
            All Tiers ({tierCounts.total})
          </button>
          <button
            className={`filter-pill ${selectedTier === 'on_device' ? 'active cyan' : ''}`}
            onClick={() => setSelectedTier('on_device')}
          >
            <Cpu size={14} />
            <span>On-Device ({tierCounts.on_device})</span>
          </button>
          <button
            className={`filter-pill ${selectedTier === 'cloud_agent' ? 'active purple' : ''}`}
            onClick={() => setSelectedTier('cloud_agent')}
          >
            <Cloud size={14} />
            <span>Cloud Agent ({tierCounts.cloud_agent})</span>
          </button>
          <button
            className={`filter-pill ${selectedTier === 'mcp_server' ? 'active amber' : ''}`}
            onClick={() => setSelectedTier('mcp_server')}
          >
            <Globe size={14} />
            <span>MCP Server ({tierCounts.mcp_server})</span>
          </button>
        </div>

        {/* Category selector */}
        <div className="category-select-wrapper">
          <Filter size={14} color="var(--text-muted)" />
          <select 
            value={selectedCategory}
            onChange={e => setSelectedCategory(e.target.value)}
            className="category-dropdown"
          >
            <option value="all">Semua Kategori</option>
            {categories.filter(c => c !== 'all').map(cat => (
              <option key={cat} value={cat}>{cat}</option>
            ))}
          </select>
        </div>
      </div>

      {/* 3. Results Summary */}
      <div className="tools-results-summary">
        <span>Menampilkan <strong>{filteredTools.length}</strong> dari {tools.length} tool terdaftar</span>
        {(searchQuery || selectedTier !== 'all' || selectedCategory !== 'all') && (
          <button 
            className="reset-filters-link"
            onClick={() => {
              setSearchQuery('');
              setSelectedTier('all');
              setSelectedCategory('all');
            }}
          >
            Reset filter
          </button>
        )}
      </div>

      {/* 4. Tools Grid */}
      {loading ? (
        <div className="loading-state glass-panel">
          <div className="pulse-dot" />
          <span>Memuat katalog tools FinGent...</span>
        </div>
      ) : filteredTools.length === 0 ? (
        <div className="empty-state glass-panel">
          <Wrench size={36} color="var(--text-muted)" />
          <h3>Tidak ada tool yang cocok</h3>
          <p>Coba gunakan kata kunci pencarian yang lain atau reset filter tier & kategori.</p>
        </div>
      ) : (
        <div className="tools-cards-grid">
          {filteredTools.map(tool => {
            const badge = getTierBadge(tool.tier);
            return (
              <div key={tool.id} className="tool-card glass-panel" id={tool.id}>
                {/* Top header of card */}
                <div className="tool-card-header">
                  <div className="tool-title-row">
                    <div className="tool-symbol-icon">
                      {tool.tier === 'on_device' ? '📱' : tool.tier === 'cloud_agent' ? '☁️' : '🌐'}
                    </div>
                    <div>
                      <div className="tool-display-name">{tool.display_name}</div>
                      <div className="tool-raw-name font-mono">{tool.name}</div>
                    </div>
                  </div>

                  <div 
                    className="tier-badge"
                    style={{
                      color: badge.color,
                      backgroundColor: badge.bg,
                      borderColor: badge.border
                    }}
                  >
                    {badge.icon}
                    <span>{badge.label}</span>
                  </div>
                </div>

                {/* Badges metadata bar */}
                <div className="tool-meta-tags">
                  <span className="meta-tag category-tag">
                    <Layers size={11} />
                    {tool.category}
                  </span>
                  <span className="meta-tag latency-tag">
                    <Clock size={11} />
                    {tool.latency}
                  </span>
                  <span className="meta-tag privacy-tag">
                    <ShieldCheck size={11} />
                    {tool.privacy}
                  </span>
                </div>

                {/* Description */}
                <p className="tool-description">{tool.description}</p>

                {/* Execution Engine */}
                <div className="tool-engine-box">
                  <span className="engine-label">Engine:</span>
                  <span className="engine-value font-mono">{tool.execution_engine}</span>
                </div>

                {/* Parameters Section */}
                <div className="tool-section">
                  <div className="section-title">
                    <Terminal size={12} />
                    <span>Parameters / Arguments ({tool.parameters.length})</span>
                  </div>

                  {tool.parameters.length === 0 ? (
                    <div className="no-params-badge font-mono">
                      Ø No parameters required (direct on-device read)
                    </div>
                  ) : (
                    <div className="params-list">
                      {tool.parameters.map((param, pIdx) => (
                        <div key={pIdx} className="param-item">
                          <div className="param-header font-mono">
                            <span className="param-name">{param.name}</span>
                            <span className="param-type">:{param.type}</span>
                            {param.required ? (
                              <span className="param-required">REQUIRED</span>
                            ) : (
                              <span className="param-optional">OPTIONAL</span>
                            )}
                          </div>
                          <div className="param-desc">{param.description}</div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* Example Prompts */}
                <div className="tool-section">
                  <div className="section-title">
                    <Sparkles size={12} />
                    <span>Contoh Pertanyaan User</span>
                  </div>
                  <div className="example-prompts-list">
                    {tool.example_queries.map((ex, eIdx) => (
                      <div 
                        key={eIdx} 
                        className="example-prompt-chip"
                        onClick={() => handleCopyPrompt(ex)}
                        title="Klik untuk menyalin pertanyaan"
                      >
                        <span>"{ex}"</span>
                        <button className="copy-icon-btn">
                          {copiedPrompt === ex ? <Check size={12} color="var(--accent-emerald)" /> : <Copy size={12} />}
                        </button>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Data Sources Badges */}
                <div className="tool-section data-sources-section">
                  <div className="section-title">
                    <Database size={12} />
                    <span>Sumber Data</span>
                  </div>
                  <div className="sources-pills">
                    {tool.data_sources.map((src, sIdx) => (
                      <span key={sIdx} className="source-pill font-mono">
                        {src}
                      </span>
                    ))}
                  </div>
                </div>

                {/* Footer action */}
                <div className="tool-card-footer">
                  <button 
                    className="inspect-schema-btn"
                    onClick={() => setSelectedToolForInspect(tool)}
                  >
                    <span>Inspect Tool Schema</span>
                    <ArrowRight size={13} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* 5. Tool Schema Inspection Modal */}
      {selectedToolForInspect && (
        <div className="modal-backdrop" onClick={() => setSelectedToolForInspect(null)}>
          <div className="modal-container glass-panel" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-title-group">
                <span className="font-mono modal-tool-name">{selectedToolForInspect.name}</span>
                <span className="modal-tool-tier">{selectedToolForInspect.tier.toUpperCase()}</span>
              </div>
              <button 
                className="modal-close-btn"
                onClick={() => setSelectedToolForInspect(null)}
              >
                ✕
              </button>
            </div>

            <div className="modal-body">
              <p style={{ color: 'var(--text-secondary)', marginBottom: '1rem', fontSize: '0.9rem' }}>
                {selectedToolForInspect.description}
              </p>

              <div className="schema-block-wrapper">
                <div className="schema-block-title">
                  <span>Apple FoundationModels / MCP Tool JSON Definition:</span>
                  <button 
                    className="copy-schema-btn"
                    onClick={() => {
                      const json = JSON.stringify(selectedToolForInspect, null, 2);
                      handleCopyPrompt(json);
                    }}
                  >
                    {copiedPrompt ? 'Copied!' : 'Copy JSON'}
                  </button>
                </div>
                <pre className="schema-pre font-mono">
                  {JSON.stringify({
                    tool: selectedToolForInspect.name,
                    tier: selectedToolForInspect.tier,
                    engine: selectedToolForInspect.execution_engine,
                    parameters: selectedToolForInspect.parameters.reduce((acc, p) => {
                      acc[p.name] = {
                        type: p.type,
                        required: p.required,
                        description: p.description
                      };
                      return acc;
                    }, {} as Record<string, any>),
                    example_user_prompts: selectedToolForInspect.example_queries,
                    data_sources: selectedToolForInspect.data_sources
                  }, null, 2)}
                </pre>
              </div>
            </div>

            <div className="modal-footer">
              <button 
                className="modal-dismiss-btn"
                onClick={() => setSelectedToolForInspect(null)}
              >
                Tutup
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
