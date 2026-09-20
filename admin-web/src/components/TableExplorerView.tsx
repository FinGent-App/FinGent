import React, { useState, useEffect } from 'react';
import type { TableOverview, TableDataResponse } from '../types';
import { fetchTables, fetchTableData, deleteTableRow } from '../api';
import { 
  Database, 
  Search, 
  RefreshCw, 
  Trash2, 
  Eye, 
  ChevronLeft, 
  ChevronRight, 
  X,
  Layers
} from 'lucide-react';

export const TableExplorerView: React.FC = () => {
  const [tables, setTables] = useState<TableOverview[]>([]);
  const [activeTable, setActiveTable] = useState<string>('news_articles');
  const [tableData, setTableData] = useState<TableDataResponse | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [inspectRow, setInspectRow] = useState<Record<string, any> | null>(null);

  // Load list of tables
  const loadTables = async () => {
    try {
      const res = await fetchTables();
      setTables(res);
      if (res.length > 0 && !res.some(t => t.table_name === activeTable)) {
        setActiveTable(res[0].table_name);
      }
    } catch (e) {
      console.error('Failed to load tables list:', e);
    }
  };

  // Load data for active table
  const loadData = async (table: string, page: number, search?: string) => {
    setLoading(true);
    try {
      const data = await fetchTableData(table, page, 25, search);
      setTableData(data);
    } catch (e) {
      console.error(`Failed to load data for ${table}:`, e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadTables();
  }, []);

  useEffect(() => {
    setCurrentPage(1);
    loadData(activeTable, 1, searchQuery);
  }, [activeTable]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setCurrentPage(1);
    loadData(activeTable, 1, searchQuery);
  };

  const handlePageChange = (newPage: number) => {
    setCurrentPage(newPage);
    loadData(activeTable, newPage, searchQuery);
  };

  const handleDelete = async (row: Record<string, any>) => {
    const rowId = row.id;
    if (!rowId) return;
    if (!window.confirm(`Hapus baris dengan ID '${rowId}' dari tabel ${activeTable}?`)) return;

    try {
      const ok = await deleteTableRow(activeTable, String(rowId));
      if (ok) {
        loadData(activeTable, currentPage, searchQuery);
        loadTables();
      }
    } catch (e) {
      alert(`Gagal menghapus baris: ${e}`);
    }
  };

  return (
    <div id="table-explorer-view">
      <div className="table-explorer-layout">
        {/* Left Sidebar: Table Navigation */}
        <div className="glass-panel" style={{ padding: '1rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1rem', color: 'var(--accent-cyan)' }}>
            <Layers size={18} />
            <span style={{ fontWeight: 700, fontSize: '0.95rem' }}>PostgreSQL Tables</span>
          </div>

          <div>
            {tables.map(t => (
              <div
                key={t.table_name}
                className={`table-sidebar-item ${activeTable === t.table_name ? 'active' : ''}`}
                onClick={() => setActiveTable(t.table_name)}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                  <Database size={14} color={activeTable === t.table_name ? 'var(--accent-cyan)' : 'var(--text-muted)'} />
                  <span style={{ fontSize: '0.85rem' }}>{t.table_name}</span>
                </div>
                <span className="table-row-count-badge">
                  {t.row_count.toLocaleString()}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Right Content: Data Grid */}
        <div className="glass-panel">
          <div className="table-controls">
            <div>
              <h2 style={{ fontSize: '1.25rem', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
                <span>{activeTable}</span>
                <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)', fontWeight: 400 }}>
                  ({tableData?.total_rows.toLocaleString() || 0} rows total)
                </span>
              </h2>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
              <form onSubmit={handleSearch} className="search-input-wrapper">
                <Search size={15} className="search-icon" />
                <input
                  type="text"
                  placeholder={`Cari di tabel ${activeTable}...`}
                  className="search-input"
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                />
              </form>

              <button
                className="pagination-btn"
                onClick={() => {
                  loadData(activeTable, currentPage, searchQuery);
                  loadTables();
                }}
                title="Refresh Table"
              >
                <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
                <span>Refresh</span>
              </button>
            </div>
          </div>

          {/* Table Data Grid */}
          <div className="data-table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th style={{ width: '80px' }}>Actions</th>
                  {tableData?.columns.map(col => (
                    <th key={col.column_name}>
                      {col.column_name}
                      <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)', marginLeft: '0.35rem' }}>
                        ({col.data_type})
                      </span>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={(tableData?.columns.length || 1) + 1} style={{ textAlign: 'center', padding: '2rem' }}>
                      Memuat data PostgreSQL...
                    </td>
                  </tr>
                ) : tableData?.rows.length === 0 ? (
                  <tr>
                    <td colSpan={(tableData?.columns.length || 1) + 1} style={{ textAlign: 'center', padding: '2rem', color: 'var(--text-muted)' }}>
                      Tidak ada baris data ditemukan di tabel ini.
                    </td>
                  </tr>
                ) : (
                  tableData?.rows.map((row, rIdx) => (
                    <tr key={row.id || rIdx}>
                      <td style={{ display: 'flex', gap: '0.35rem' }}>
                        <button
                          onClick={() => setInspectRow(row)}
                          style={{ background: 'transparent', border: 'none', color: 'var(--accent-cyan)', cursor: 'pointer' }}
                          title="Lihat Detail JSON"
                        >
                          <Eye size={15} />
                        </button>
                        {row.id && (
                          <button
                            onClick={() => handleDelete(row)}
                            style={{ background: 'transparent', border: 'none', color: 'var(--accent-rose)', cursor: 'pointer' }}
                            title="Hapus Baris"
                          >
                            <Trash2 size={15} />
                          </button>
                        )}
                      </td>

                      {tableData.columns.map(col => {
                        const val = row[col.column_name];
                        let rendered: React.ReactNode = String(val ?? '');

                        // Highlight Tickers array as pill badges
                        if (col.column_name === 'tickers' && Array.isArray(val)) {
                          rendered = (
                            <div style={{ display: 'flex', gap: '0.25rem' }}>
                              {val.map(t => (
                                <span key={t} className="badge badge-idx" style={{ padding: '0.1rem 0.4rem', fontSize: '0.7rem' }}>
                                  {t}
                                </span>
                              ))}
                            </div>
                          );
                        } else if (typeof val === 'object' && val !== null) {
                          rendered = <span style={{ color: '#94a3b8' }}>{JSON.stringify(val)}</span>;
                        }

                        return <td key={col.column_name}>{rendered}</td>;
                      })}
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          {/* Pagination Bar */}
          <div className="pagination-bar">
            <span>
              Halaman {currentPage} dari {tableData?.total_pages || 1} ({tableData?.total_rows.toLocaleString() || 0} baris)
            </span>

            <div style={{ display: 'flex', gap: '0.5rem' }}>
              <button
                className="pagination-btn"
                disabled={currentPage <= 1}
                onClick={() => handlePageChange(currentPage - 1)}
              >
                <ChevronLeft size={14} />
                <span>Sebelumnya</span>
              </button>

              <button
                className="pagination-btn"
                disabled={currentPage >= (tableData?.total_pages || 1)}
                onClick={() => handlePageChange(currentPage + 1)}
              >
                <span>Berikutnya</span>
                <ChevronRight size={14} />
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Row Inspect Modal */}
      {inspectRow && (
        <div className="modal-backdrop" onClick={() => setInspectRow(null)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h3 style={{ fontSize: '1.1rem', fontWeight: 600 }}>Detail Baris PostgreSQL ({activeTable})</h3>
              <button
                onClick={() => setInspectRow(null)}
                style={{ background: 'transparent', border: 'none', color: 'var(--text-primary)', cursor: 'pointer' }}
              >
                <X size={18} />
              </button>
            </div>
            <div className="modal-body">
              <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>
                {JSON.stringify(inspectRow, null, 2)}
              </pre>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
