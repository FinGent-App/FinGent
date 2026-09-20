import React, { useState, useEffect } from 'react';
import type { FeedStatus } from '../types';
import { fetchFeedsStatus, triggerFeedSync } from '../api';
import { Rss, RefreshCw, CheckCircle2, ExternalLink } from 'lucide-react';

export const RSSFeedsView: React.FC = () => {
  const [feeds, setFeeds] = useState<FeedStatus[]>([]);
  const [syncing, setSyncing] = useState<boolean>(false);
  const [message, setMessage] = useState<string | null>(null);

  const loadFeeds = async () => {
    try {
      const data = await fetchFeedsStatus();
      setFeeds(data);
    } catch (e) {
      console.error('Failed to load feeds status:', e);
    }
  };

  useEffect(() => {
    loadFeeds();
  }, []);

  const handleSyncAll = async () => {
    setSyncing(true);
    setMessage('Menjalankan sinkronisasi 12 provider RSS di background...');
    try {
      await triggerFeedSync();
      setTimeout(() => {
        loadFeeds();
        setSyncing(false);
        setMessage('Sinkronisasi selesai! Artikel baru telah di-ingest ke PostgreSQL.');
      }, 3000);
    } catch (e) {
      setMessage(`Gagal memicu sinkronisasi: ${e}`);
      setSyncing(false);
    }
  };

  return (
    <div id="rss-feeds-view">
      <div className="glass-panel" style={{ marginBottom: '1.5rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <h2 style={{ fontSize: '1.25rem', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
              <Rss size={20} color="var(--accent-cyan)" />
              <span>Multi-Source Financial RSS Ingestion Pipeline (12 Feeds)</span>
            </h2>
            <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginTop: '0.35rem' }}>
              Memantau status kesehatan & deduplikasi SHA-256 seluruh feed berita Indonesia (IDX) dan US/Global.
            </div>
          </div>

          <button
            id="sync-all-feeds-btn"
            className="btn-sync"
            onClick={handleSyncAll}
            disabled={syncing}
          >
            <RefreshCw size={15} className={syncing ? 'animate-spin' : ''} />
            <span>{syncing ? 'Syncing Feeds...' : 'Sync All Feeds Now'}</span>
          </button>
        </div>

        {message && (
          <div style={{ marginTop: '1rem', padding: '0.65rem 1rem', background: 'rgba(0, 210, 255, 0.1)', border: '1px solid rgba(0, 210, 255, 0.25)', borderRadius: '8px', fontSize: '0.825rem', color: 'var(--accent-cyan)' }}>
            {message}
          </div>
        )}
      </div>

      {/* Grid of 12 Feeds */}
      <div className="feeds-grid">
        {feeds.map(feed => {
          const isIDX = feed.market === 'IDX';
          return (
            <div key={feed.name} className="feed-card">
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.75rem' }}>
                <span className={`badge ${isIDX ? 'badge-idx' : 'badge-us'}`}>
                  {isIDX ? '🇮🇩 IDX Feed' : '🇺🇸 US/Global Feed'}
                </span>

                <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem', color: 'var(--accent-emerald)', fontSize: '0.75rem', fontWeight: 600 }}>
                  <CheckCircle2 size={13} />
                  <span>ONLINE</span>
                </div>
              </div>

              <div style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--text-primary)', marginBottom: '0.25rem' }}>
                {feed.name}
              </div>

              <div style={{ fontSize: '0.775rem', color: 'var(--text-muted)', marginBottom: '0.85rem' }}>
                Kategori: {feed.category}
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', padding: '0.65rem 0.85rem', background: 'rgba(255, 255, 255, 0.65)', border: '1px solid rgba(0, 0, 0, 0.06)', borderRadius: '8px', fontSize: '0.8rem', marginBottom: '0.85rem' }}>
                <span style={{ color: 'var(--text-secondary)' }}>Artikel di PostgreSQL:</span>
                <span style={{ fontWeight: 700, color: 'var(--text-primary)', fontFamily: 'var(--font-mono)' }}>
                  {feed.articles_in_db.toLocaleString()}
                </span>
              </div>

              <div style={{ fontSize: '0.725rem', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <span>Latest: {feed.latest_article_at ? new Date(feed.latest_article_at).toLocaleDateString() : 'Active'}</span>
                <a 
                  href={feed.feed_url} 
                  target="_blank" 
                  rel="noreferrer" 
                  style={{ color: 'var(--accent-cyan)', textDecoration: 'none', display: 'flex', alignItems: 'center', gap: '0.2rem' }}
                >
                  <span>Feed URL</span>
                  <ExternalLink size={10} />
                </a>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
