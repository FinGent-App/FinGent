import type { AppTool, AppToolsResponse } from './types';

export const FALLBACK_APP_TOOLS: AppTool[] = [
  // --- 1. Local On-Device Tools (Apple FoundationModels Native) ---
  {
    id: 'tool-get-portfolio-summary',
    name: 'getPortfolioSummary',
    display_name: 'Portfolio Summary',
    tier: 'on_device',
    category: 'Portfolio',
    execution_engine: 'Apple FoundationModels (Swift Native)',
    latency: '0 ms (Instant)',
    privacy: '100% On-Device (Data stays on phone)',
    description: 'Mengambil ringkasan portofolio pengguna: total nilai pasar, total modal investasi, keuntungan/kerugian (P&L) kumulatif, dan status portofolio.',
    parameters: [],
    example_queries: [
      'Berapa total nilai portofolio saya?',
      'Ringkasan portofolio saya sekarang',
      'Apakah portofolio saya sedang profit atau loss?'
    ],
    data_sources: ['PortfolioRepository (Local Swift)', 'MarketDataRepository']
  },
  {
    id: 'tool-get-holding',
    name: 'getHolding',
    display_name: 'Stock Holding Detail',
    tier: 'on_device',
    category: 'Portfolio',
    execution_engine: 'Apple FoundationModels (Swift Native)',
    latency: '0 ms (Instant)',
    privacy: '100% On-Device (Data stays on phone)',
    description: 'Mendapatkan rincian posisi kepemilikan saham spesifik (lot/lembar, harga beli rata-rata, nilai pasar saat ini, unrealized P&L) atau seluruh saham (\'ALL\').',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "Simbol ticker saham yang dicari (misal 'BBCA', 'MU') atau gunakan 'ALL' untuk melihat seluruh posisi."
      }
    ],
    example_queries: [
      'Berapa lembar saham BBCA yang saya punya?',
      'Cek posisi saham Micron (MU)',
      'Tampilkan semua saham di portofolio saya'
    ],
    data_sources: ['PortfolioRepository (Local Swift)', 'StockTickerExtractor']
  },
  {
    id: 'tool-get-portfolio-performance',
    name: 'getPortfolioPerformance',
    display_name: 'Portfolio Performance',
    tier: 'on_device',
    category: 'Portfolio',
    execution_engine: 'Apple FoundationModels (Swift Native)',
    latency: '0 ms (Instant)',
    privacy: '100% On-Device (Data stays on phone)',
    description: 'Menghitung performa return berbobot portofolio beserta breakdown per emiten untuk periode harian, mingguan, bulanan, YTD, atau tahunan.',
    parameters: [
      {
        name: 'period',
        type: 'string',
        required: true,
        description: "Periode performa: 'daily', 'weekly', 'monthly', 'ytd', atau 'yearly'."
      }
    ],
    example_queries: [
      'Bagaimana performa portofolio saya minggu ini?',
      'Berapa return portofolio sejak awal tahun (YTD)?',
      'Cek kinerja portofolio bulanan'
    ],
    data_sources: ['PortfolioRepository', 'MarketDataRepository']
  },
  {
    id: 'tool-get-portfolio-allocation',
    name: 'getPortfolioAllocation',
    display_name: 'Portfolio Allocation',
    tier: 'on_device',
    category: 'Portfolio',
    execution_engine: 'Apple FoundationModels (Swift Native)',
    latency: '0 ms (Instant)',
    privacy: '100% On-Device (Data stays on phone)',
    description: 'Menghitung diversifikasi portofolio berdasarkan breakdown sektor industri dan bobot persentase tiap saham.',
    parameters: [],
    example_queries: [
      'Bagaimana alokasi sektor dalam portofolio saya?',
      'Berapa persen porsi saham teknologi di portofolio?',
      'Tampilkan komposisi saham terbesar saya'
    ],
    data_sources: ['PortfolioRepository', 'MarketDataRepository']
  },
  {
    id: 'tool-get-portfolio-movers',
    name: 'getPortfolioMovers',
    display_name: 'Portfolio Movers',
    tier: 'on_device',
    category: 'Portfolio',
    execution_engine: 'Apple FoundationModels (Swift Native)',
    latency: '0 ms (Instant)',
    privacy: '100% On-Device (Data stays on phone)',
    description: 'Mengidentifikasi saham yang bergerak paling menguntungkan (top gainers) atau paling tertekan (top losers) di dalam portofolio pengguna hari ini.',
    parameters: [
      {
        name: 'direction',
        type: 'string',
        required: true,
        description: "Filter arah pergerakan: 'gainers', 'losers', atau 'all'."
      }
    ],
    example_queries: [
      'Saham apa yang paling naik di portofolio saya hari ini?',
      'Siapa top loser di portofolio saya?',
      'Tampilkan saham yang bergerak signifikan hari ini'
    ],
    data_sources: ['PortfolioRepository', 'MarketDataRepository']
  },
  {
    id: 'tool-get-unrealized-gain',
    name: 'getUnrealizedGain',
    display_name: 'Unrealized Gain / Loss',
    tier: 'on_device',
    category: 'Portfolio',
    execution_engine: 'Apple FoundationModels (Swift Native)',
    latency: '0 ms (Instant)',
    privacy: '100% On-Device (Data stays on phone)',
    description: 'Menghitung keuntungan atau kerugian belum terealisasi (floating P&L dalam nominal Rupiah dan persentase) per saham atau total portofolio.',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "Simbol ticker saham (misal 'MU', 'BBCA') atau gunakan 'ALL' untuk total portofolio."
      }
    ],
    example_queries: [
      'Berapa floating profit saham BBCA saya?',
      'Hitung total floating loss/gain seluruh portofolio',
      'Apakah saham MU saya sedang untung?'
    ],
    data_sources: ['PortfolioRepository', 'MarketDataRepository']
  },
  {
    id: 'tool-get-stock-quote',
    name: 'getStockQuote',
    display_name: 'Live Stock Quote',
    tier: 'on_device',
    category: 'Market Data',
    execution_engine: 'Apple FoundationModels + Backend Yahoo API',
    latency: '50 - 150 ms',
    privacy: 'Anonymized Ticker Request',
    description: 'Mengambil harga saham terkini (live / real-time quote), perubahan 24 jam, persentase naik/turun, rentang harga harian (day low/high), dan volume perdagangan.',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "Kode emiten saham (misal 'BBCA', 'TLKM', 'NVDA', 'AAPL')."
      }
    ],
    example_queries: [
      'Berapa harga saham BBCA sekarang?',
      'Cek harga terkini saham Apple (AAPL)',
      'Berapa pergerakan saham GOTO hari ini?'
    ],
    data_sources: ['Yahoo Finance API', 'Local Market Cache']
  },
  {
    id: 'tool-get-stock-performance',
    name: 'getStockPerformance',
    display_name: 'Historical Stock Performance',
    tier: 'on_device',
    category: 'Market Data',
    execution_engine: 'Apple FoundationModels (Swift Native)',
    latency: '0 ms (Cached) / 100 ms',
    privacy: 'Anonymized Ticker Request',
    description: 'Mengambil persentase return historis saham individu untuk periode harian, mingguan, bulanan, year-to-date (YTD), atau 1 tahun.',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "Simbol ticker saham (misal 'BBCA', 'ASII')."
      },
      {
        name: 'period',
        type: 'string',
        required: true,
        description: "Rentang waktu: 'daily', 'weekly', 'monthly', 'ytd', 'yearly', atau 'all'."
      }
    ],
    example_queries: [
      'Bagaimana performa saham BBCA 1 tahun terakhir?',
      'Berapa return saham NVDA dalam 1 bulan ini?',
      'Tampilkan rekap performa lengkap saham ASII'
    ],
    data_sources: ['MarketDataRepository', 'Yahoo Finance']
  },

  // --- 2. Cloud Research Analyst Agent (Gemini + Milvus Hybrid RAG) ---
  {
    id: 'tool-consult-cloud-analyst',
    name: 'consultCloudAnalyst',
    display_name: 'Cloud Research Analyst Agent',
    tier: 'cloud_agent',
    category: 'Deep Research',
    execution_engine: 'Google Gemini 1.5/3.6 Flash + Zilliz Milvus Vector RAG',
    latency: '800 - 1,500 ms',
    privacy: 'Multi-Modal Synthesized & Grounded (Zero Hallucination)',
    description: 'Agen riset cloud mendalam yang mengorkestrasi pencarian vektor Milvus (SEC 10-K/8-K, puluhan ribu artikel berita finansial), rasio valuasi fundamental live, dan sintesis multi-modal cerdas dengan bukti sitasi berita terverifikasi.',
    parameters: [
      {
        name: 'query',
        type: 'string',
        required: true,
        description: 'Pertanyaan riset finansial atau isu pasar mendalam.'
      },
      {
        name: 'ticker',
        type: 'string',
        required: false,
        description: "Ticker saham spesifik yang menjadi fokus analisa (misal 'MU', 'BBCA', 'NVDA')."
      }
    ],
    example_queries: [
      'Kenapa saham Micron (MU) naik tajam kemarin?',
      'Bagaimana prospek NVDA dan persaingannya di data center?',
      'Analisis sentimen dan berita terbaru seputar laba BBRI'
    ],
    data_sources: ['Google Gemini 3.6 Flash', 'Zilliz Cloud Milvus (Vector RAG)', 'SEC Filings (10-K, 8-K)', 'Supabase News DB', 'Yahoo Finance']
  },

  // --- 3. Model Context Protocol (MCP) Remote Tools ---
  {
    id: 'tool-mcp-search-rag',
    name: 'search_financial_knowledge_rag',
    display_name: 'Financial Knowledge Vector RAG',
    tier: 'mcp_server',
    category: 'Deep Research',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '200 - 400 ms',
    privacy: 'Dense Semantic Embeddings RAG',
    description: 'Melakukan dense vector semantic search ke database Zilliz Cloud Milvus untuk menemukan artikel berita finansial, pengumuman bursa, dan pengungkapan regulasi SEC.',
    parameters: [
      {
        name: 'query',
        type: 'string',
        required: true,
        description: 'Topik atau kata kunci pencarian finansial semantik.'
      },
      {
        name: 'limit',
        type: 'integer',
        required: false,
        description: 'Jumlah dokumen teratas yang dikembalikan (default: 5).'
      }
    ],
    example_queries: [
      'Cari berita akuisisi atau aksi korporasi bank BUMN',
      'Filing SEC terkait belanja modal AI Nvidia',
      'Sentimen perang dagang terhadap semikonduktor'
    ],
    data_sources: ['Zilliz Cloud Milvus (768-dim Vectors)', 'BGE-base-en/id Embeddings']
  },
  {
    id: 'tool-mcp-simulate-macro-risk',
    name: 'simulate_macro_portfolio_risk',
    display_name: 'Macro Risk & Scenario Simulator',
    tier: 'mcp_server',
    category: 'Risk & Scenario',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '300 - 500 ms',
    privacy: 'Portfolio Exposure Simulation Engine',
    description: 'Menghitung estimasi tingkat risiko dan proyeksi dampak skenario makroekonomi (kenaikan suku bunga The Fed / BI, inflasi tinggi, depresiasi Rupiah terhadap Dollar) terhadap saham-saham portofolio pengguna.',
    parameters: [
      {
        name: 'event',
        type: 'string',
        required: true,
        description: "Skenario makroekonomi (misal: 'The Fed raises interest rates 50 bps', 'Inflasi naik tinggi', 'Depresiasi Rupiah')."
      },
      {
        name: 'user_id',
        type: 'string',
        required: false,
        description: "ID pengguna portofolio (default: 'default_user')."
      }
    ],
    example_queries: [
      'Bagaimana jika suku bunga BI naik 50 bps terhadap portofolio saya?',
      'Simulasikan dampak pelemahan kurs Rupiah ke saham-saham saya',
      'Apa pengaruh lonjakan inflasi terhadap sektor perbankan dan konsumsi?'
    ],
    data_sources: ['Supabase PostgreSQL Portfolio', 'Yahoo Finance Live Quotes', 'Macro Sensitivity Model']
  },
  {
    id: 'tool-mcp-analyze-news-sentiment',
    name: 'analyze_news_sentiment_impact',
    display_name: 'News Sentiment & Price Impact',
    tier: 'mcp_server',
    category: 'News & Sentiment',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '250 - 450 ms',
    privacy: 'Catalyst & Sentiment Analysis',
    description: 'Menganalisis bias sentimen (BULLISH / BEARISH / NEUTRAL), kata kunci katalis pemberitaan, dan mendeteksi saham-saham yang terpengaruh beserta live harga pasar.',
    parameters: [
      {
        name: 'topic_or_headline',
        type: 'string',
        required: true,
        description: 'Judul berita, isu pasar, atau topik yang ingin dianalisis dampaknya.'
      }
    ],
    example_queries: [
      'Analisis sentimen rilis laporan keuangan kuartalan Apple',
      'Dampak berita kenaikan harga batubara ke emiten energi',
      'Sentimen isu pemangkasan suku bunga acuan'
    ],
    data_sources: ['Zilliz Cloud Milvus', 'Yahoo Finance Quotes', 'Supabase News DB']
  },
  {
    id: 'tool-mcp-compare-stocks',
    name: 'compare_stocks_side_by_side',
    display_name: 'Side-by-Side Stock Comparison',
    tier: 'mcp_server',
    category: 'Market Data',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '300 - 600 ms',
    privacy: 'Market Fundamentals Aggregation',
    description: 'Membandingkan 2 atau lebih saham secara berdampingan: harga, pergerakan 24 jam, valuasi P/E, PBV, ROE, EPS, Free Cash Flow, Dividend Yield, dan Market Cap.',
    parameters: [
      {
        name: 'tickers',
        type: 'array<string>',
        required: true,
        description: "Daftar simbol ticker saham yang dibandingkan (misal ['BBCA', 'BMRI', 'BBRI'] atau ['AAPL', 'MSFT'])."
      }
    ],
    example_queries: [
      'Bandingkan saham BBCA dan BMRI dari segi valuasi',
      'Komparasi sektor teknologi: NVDA vs AMD vs INTC',
      'Bandingkan dividen yield ASII, BBRI, dan TLKM'
    ],
    data_sources: ['Yahoo Finance Fundamentals', 'Batch Quote Service']
  },
  {
    id: 'tool-mcp-get-stock-fundamentals',
    name: 'get_stock_valuation_fundamentals',
    display_name: 'Valuation Fundamentals Multiples',
    tier: 'mcp_server',
    category: 'Market Data',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '150 - 300 ms',
    privacy: 'Market Fundamentals Aggregation',
    description: 'Mengambil metrik valuasi lengkap: Trailing P/E, Forward P/E, Price to Book (PBV), Return on Equity (ROE), EPS, Free Cash Flow, Dividend Yield, dan Kapitalisasi Pasar.',
    parameters: [
      {
        name: 'ticker_or_name',
        type: 'string',
        required: true,
        description: "Kode emiten atau nama perusahaan (misal 'BBCA', 'TLKM', 'AAPL')."
      }
    ],
    example_queries: [
      'Berapa P/E ratio dan PBV saham BBCA?',
      'Cek rasio fundamental keuangan TLKM',
      'Berapa dividend yield saham ASII?'
    ],
    data_sources: ['Yahoo Finance Fundamentals Engine']
  },
  {
    id: 'tool-mcp-search-stocks',
    name: 'search_stocks_directory',
    display_name: 'Stocks Search Directory',
    tier: 'mcp_server',
    category: 'Market Data',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '100 - 200 ms',
    privacy: 'Public Equities Search',
    description: "Pencarian saham cerdas berdasarkan nama perusahaan, alias brand, atau simbol ticker (misal 'bca' -> BBCA.JK, 'micron' -> MU).",
    parameters: [
      {
        name: 'query',
        type: 'string',
        required: true,
        description: 'Nama perusahaan atau query pencarian.'
      },
      {
        name: 'limit',
        type: 'integer',
        required: false,
        description: 'Batas hasil pencarian (default: 5).'
      }
    ],
    example_queries: [
      'Cari saham BCA atau bank mandiri',
      'Cari kode saham produsen memori Micron',
      'Cari emiten mobil listrik'
    ],
    data_sources: ['Yahoo Finance Search API', 'Local Ticker Dictionary']
  },
  {
    id: 'tool-mcp-get-market-leaders',
    name: 'get_market_leaders',
    display_name: 'Market Leaders & Movers',
    tier: 'mcp_server',
    category: 'Market Data',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '150 - 300 ms',
    privacy: 'Bursa Composite Market Data',
    description: 'Mengambil daftar saham top gainers, top losers, dan pergerakan indeks acuan IHSG atau pasar global.',
    parameters: [
      {
        name: 'mover_type',
        type: 'string',
        required: false,
        description: "'gainers' untuk saham tercuan atau 'losers' untuk saham tertekan (default: 'gainers')."
      }
    ],
    example_queries: [
      'Tampilkan saham top gainers hari ini',
      'Siapa saja saham yang turun paling dalam?',
      'Bagaimana kondisi indeks IHSG hari ini?'
    ],
    data_sources: ['Yahoo Finance Market Movers Service', 'Bursa Index Feed']
  },
  {
    id: 'tool-mcp-get-portfolio-news',
    name: 'get_user_portfolio_news',
    display_name: 'User Portfolio News Feed',
    tier: 'mcp_server',
    category: 'News & Sentiment',
    execution_engine: 'FastMCP Server (JSON-RPC 2.0 / SSE)',
    latency: '200 - 400 ms',
    privacy: 'Personalized to User Portfolio',
    description: 'Mengambil berita terkini yang secara khusus difilter hanya untuk saham-saham yang dimiliki di portofolio aktif pengguna.',
    parameters: [
      {
        name: 'user_id',
        type: 'string',
        required: false,
        description: "ID pengguna (default: 'default_user')."
      },
      {
        name: 'ticker',
        type: 'string',
        required: false,
        description: 'Filter opsional untuk ticker spesifik.'
      }
    ],
    example_queries: [
      'Berita apa yang paling relevan untuk portofolio saya hari ini?',
      'Tampilkan sentimen berita seputar saham-saham yang saya miliki'
    ],
    data_sources: ['Supabase PostgreSQL Portfolio', 'Supabase News Articles DB']
  },
  {
    id: 'tool-mcp-analyze-technicals',
    name: 'analyze_stock_market_technicals',
    display_name: 'Market Technicals & Trend Signals',
    tier: 'mcp_server',
    category: 'Market Data',
    execution_engine: 'Enterprise Data Warehouse (BigQuery / Lakehouse)',
    latency: '100 - 300 ms',
    privacy: 'Columnar Historical Analytics Engine',
    description: 'Menganalisis pergerakan harga historis saham dari Data Warehouse: menghitung Moving Average (MA20, MA50, MA200), mendeteksi sinyal Golden Cross / Death Cross, momentum RSI 14 (Overbought/Oversold), Support/Resistance 60 hari, dan lonjakan volume breakout.',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "Simbol kode emiten saham (misal: 'BBCA', 'NVDA', 'TLKM', 'MU')."
      },
      {
        name: 'timeframe',
        type: 'string',
        required: false,
        description: "Periode timeframe analisis (default: '3M')."
      }
    ],
    example_queries: [
      'Bagaimana tren analisis teknikal saham BBCA saat ini?',
      'Apakah saham NVDA membentuk sinyal Golden Cross?',
      'Cek level support, resistance, dan RSI saham TLKM'
    ],
    data_sources: ['Google BigQuery Data Warehouse', 'Historical OHLCV Store', 'PySpark Features Engine']
  }
];

export const FALLBACK_APP_TOOLS_RESPONSE: AppToolsResponse = {
  count: FALLBACK_APP_TOOLS.length,
  tier_breakdown: {
    on_device: FALLBACK_APP_TOOLS.filter(t => t.tier === 'on_device').length,
    cloud_agent: FALLBACK_APP_TOOLS.filter(t => t.tier === 'cloud_agent').length,
    mcp_server: FALLBACK_APP_TOOLS.filter(t => t.tier === 'mcp_server').length
  },
  tools: FALLBACK_APP_TOOLS
};
