import React from 'react';
import { Database, Rss, Cpu, Wrench, Activity, Layers } from 'lucide-react';

interface NavbarProps {
  activeTab: 'llmops' | 'tables' | 'feeds' | 'tools';
  setActiveTab: (tab: 'llmops' | 'tables' | 'feeds' | 'tools') => void;
  sseConnected: boolean;
}

export const Navbar: React.FC<NavbarProps> = ({ activeTab, setActiveTab, sseConnected }) => {
  return (
    <aside className="app-sidebar" id="admin-sidebar">
      {/* 1. Brand Section */}
      <div className="sidebar-brand">
        <div className="brand-logo-badge" id="brand-logo">
          ⚡
        </div>
        <div className="brand-info">
          <div className="brand-title">FinGent Admin</div>
          <div className="brand-subtitle">Intelligence & Lakehouse</div>
        </div>
      </div>

      {/* 2. Main Navigation Section (Vertical) */}
      <div className="sidebar-menu-group">
        <div className="sidebar-menu-heading">
          <Layers size={12} />
          <span>CORE NAVIGATION</span>
        </div>

        <nav className="sidebar-nav-tabs" id="nav-tabs-container">
          <button
            id="tab-tools-btn"
            className={`sidebar-nav-btn ${activeTab === 'tools' ? 'active' : ''}`}
            onClick={() => setActiveTab('tools')}
          >
            <div className="btn-icon-wrapper">
              <Wrench size={16} />
            </div>
            <div className="btn-label-group">
              <span className="btn-main-label">App Tools</span>
              <span className="btn-sub-label">Capabilities Matrix</span>
            </div>
            <span className="sidebar-badge tools-badge">18</span>
          </button>

          <button
            id="tab-llmops-btn"
            className={`sidebar-nav-btn ${activeTab === 'llmops' ? 'active' : ''}`}
            onClick={() => setActiveTab('llmops')}
          >
            <div className="btn-icon-wrapper">
              <Cpu size={16} />
            </div>
            <div className="btn-label-group">
              <span className="btn-main-label">LLMOps & Trace</span>
              <span className="btn-sub-label">Agent Flowcharts & Costs</span>
            </div>
          </button>

          <button
            id="tab-tables-btn"
            className={`sidebar-nav-btn ${activeTab === 'tables' ? 'active' : ''}`}
            onClick={() => setActiveTab('tables')}
          >
            <div className="btn-icon-wrapper">
              <Database size={16} />
            </div>
            <div className="btn-label-group">
              <span className="btn-main-label">PostgreSQL Tables</span>
              <span className="btn-sub-label">Data Explorer & Records</span>
            </div>
          </button>

          <button
            id="tab-feeds-btn"
            className={`sidebar-nav-btn ${activeTab === 'feeds' ? 'active' : ''}`}
            onClick={() => setActiveTab('feeds')}
          >
            <div className="btn-icon-wrapper">
              <Rss size={16} />
            </div>
            <div className="btn-label-group">
              <span className="btn-main-label">RSS Feeds</span>
              <span className="btn-sub-label">IDX & US Ingestion</span>
            </div>
            <span className="sidebar-badge feeds-badge">12</span>
          </button>
        </nav>
      </div>

      {/* 3. Platform Architecture Health Status */}
      <div className="sidebar-menu-group data-infra-group">
        <div className="sidebar-menu-heading">
          <Activity size={12} />
          <span>DATA PLATFORM ENGINE</span>
        </div>
        <div className="infra-status-list">
          <div className="infra-status-item">
            <div className="infra-indicator active" />
            <span className="infra-name">Azure ADLS Gen2</span>
            <span className="infra-tag">Medallion</span>
          </div>
          <div className="infra-status-item">
            <div className="infra-indicator active" />
            <span className="infra-name">Google BigQuery</span>
            <span className="infra-tag">OLAP DWH</span>
          </div>
          <div className="infra-status-item">
            <div className="infra-indicator active" />
            <span className="infra-name">Zilliz Milvus</span>
            <span className="infra-tag">Hybrid RAG</span>
          </div>
        </div>
      </div>

      {/* 4. Sidebar Footer with Live SSE status */}
      <div className="sidebar-footer">
        <div className={`sse-badge ${!sseConnected ? 'disconnected' : ''}`} id="sse-status-badge">
          <div className={`pulse-dot ${!sseConnected ? 'disconnected' : ''}`} />
          <span>{sseConnected ? 'LIVE STREAM CONNECTED' : 'RECONNECTING...'}</span>
        </div>
        <div className="sidebar-version-tag">
          <span>FinGent v2.4 Enterprise</span>
        </div>
      </div>
    </aside>
  );
};
