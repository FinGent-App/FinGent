import React from 'react';
import { Database, Rss, Cpu, Wrench } from 'lucide-react';

interface NavbarProps {
  activeTab: 'llmops' | 'tables' | 'feeds' | 'tools';
  setActiveTab: (tab: 'llmops' | 'tables' | 'feeds' | 'tools') => void;
  sseConnected: boolean;
}

export const Navbar: React.FC<NavbarProps> = ({ activeTab, setActiveTab, sseConnected }) => {
  return (
    <nav className="navbar" id="admin-navbar">
      <div className="brand-section">
        <div className="brand-logo-badge" id="brand-logo">
          ⚡
        </div>
        <div>
          <div className="brand-title">FinGent Admin Intelligence</div>
          <div className="brand-subtitle">LLMOps & App Tools Explorer</div>
        </div>
      </div>

      <div className="nav-tabs" id="nav-tabs-container">
        <button
          id="tab-tools-btn"
          className={`nav-tab-btn ${activeTab === 'tools' ? 'active' : ''}`}
          onClick={() => setActiveTab('tools')}
        >
          <Wrench size={16} />
          <span>App Tools (18)</span>
        </button>

        <button
          id="tab-llmops-btn"
          className={`nav-tab-btn ${activeTab === 'llmops' ? 'active' : ''}`}
          onClick={() => setActiveTab('llmops')}
        >
          <Cpu size={16} />
          <span>LLMOps & Tool Trace</span>
        </button>

        <button
          id="tab-tables-btn"
          className={`nav-tab-btn ${activeTab === 'tables' ? 'active' : ''}`}
          onClick={() => setActiveTab('tables')}
        >
          <Database size={16} />
          <span>PostgreSQL Tables</span>
        </button>

        <button
          id="tab-feeds-btn"
          className={`nav-tab-btn ${activeTab === 'feeds' ? 'active' : ''}`}
          onClick={() => setActiveTab('feeds')}
        >
          <Rss size={16} />
          <span>RSS Feeds (12)</span>
        </button>
      </div>

      <div className="nav-actions">
        <div className={`sse-badge ${!sseConnected ? 'disconnected' : ''}`} id="sse-status-badge">
          <div className={`pulse-dot ${!sseConnected ? 'disconnected' : ''}`} />
          <span>{sseConnected ? 'LIVE SSE CONNECTED' : 'RECONNECTING...'}</span>
        </div>
      </div>
    </nav>
  );
};
