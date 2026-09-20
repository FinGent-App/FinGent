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
    description: 'Gets the overall portfolio summary. Use ONLY when user explicitly asks about overall portfolio summary or total net worth, NOT for specific stock questions.',
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
    description: "Gets details of a specific stock holding by ticker symbol (e.g. 'MU', 'BBCA'). Only use 'ALL' when the user explicitly asks to view all portfolio holdings.",
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "The stock ticker symbol to look up, e.g. 'MU' or 'BBCA'. Use 'ALL' ONLY if user asks to see all holdings."
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
    description: 'Gets portfolio performance (return percentage) for a given time period. Valid periods: daily, weekly, monthly, ytd, yearly.',
    parameters: [
      {
        name: 'period',
        type: 'string',
        required: true,
        description: "Time period: daily, weekly, monthly, ytd, or yearly."
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
    description: 'Gets the portfolio allocation breakdown by sector and stock. Use ONLY when user explicitly asks about overall portfolio allocation.',
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
    description: 'Gets the top movers (gainers and losers) in the portfolio. Use ONLY when user explicitly asks about portfolio movers.',
    parameters: [
      {
        name: 'direction',
        type: 'string',
        required: true,
        description: "Filter direction: 'gainers', 'losers', or 'all'."
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
    description: "Gets the unrealized gain or loss for a specific stock ticker symbol (e.g. 'MU') or the entire portfolio ('ALL').",
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "Stock ticker to check, e.g. 'MU'. Use 'ALL' ONLY if user asks for full portfolio P&L."
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
    description: 'Gets the current stock quote including price, change, volume, and intraday range for a given ticker symbol.',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "The stock ticker symbol, e.g. 'BBCA', 'GOTO', 'TLKM', 'AAPL', 'NVDA'."
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
    description: 'Gets the performance (return percentage) of a stock over different time periods: daily, weekly, monthly, ytd, yearly.',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "The stock ticker symbol."
      },
      {
        name: 'period',
        type: 'string',
        required: true,
        description: "Time period: 'daily', 'weekly', 'monthly', 'ytd', 'yearly', or 'all'."
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
    description: 'Consults the specialized FinGent Cloud Research Agent (powered by Google Gemini with Vector RAG, SEC 10-K/8-K regulatory filings, live market fundamentals, and macroeconomic scenario simulation) for deep financial analysis, valuation assessments, SEC regulatory insights, or complex market research.',
    parameters: [
      {
        name: 'query',
        type: 'string',
        required: true,
        description: 'The specific financial query, research topic, or complex question to analyze deeply.'
      },
      {
        name: 'ticker',
        type: 'string',
        required: false,
        description: "Optional stock ticker symbol to focus the research on, e.g. 'BBCA', 'AAPL', 'NVDA', 'MU', 'GOTO'."
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
    description: 'Performs dense vector semantic search across news articles, market disclosures, and SEC filings (Form 10-K, 10-Q, 8-K) stored in Zilliz Cloud Milvus.',
    parameters: [
      {
        name: 'query',
        type: 'string',
        required: true,
        description: 'Financial topic or semantic keyword query.'
      },
      {
        name: 'limit',
        type: 'integer',
        required: false,
        description: 'Maximum number of top matching documents to return (default: 5).'
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
    description: "Calculates estimated risk level and projected return impact of macroeconomic events (e.g., Fed interest rate hikes, inflation, currency devaluation, recession) against the user's specific stock portfolio holdings.",
    parameters: [
      {
        name: 'event',
        type: 'string',
        required: true,
        description: "Macroeconomic scenario (e.g., 'The Fed raises interest rates 50 bps', 'High Inflation Surge', 'Rupiah Depreciation')."
      },
      {
        name: 'user_id',
        type: 'string',
        required: false,
        description: "Portfolio user ID (default: 'default_user')."
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
    description: 'Analyzes sentiment score, bullish/bearish bias, and potential price impact of news headlines or market topics.',
    parameters: [
      {
        name: 'topic_or_headline',
        type: 'string',
        required: true,
        description: 'News headline, market topic, or catalyst to analyze.'
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
    description: 'Compares two or more stocks side-by-side on price, valuation ratios, returns, and fundamentals.',
    parameters: [
      {
        name: 'tickers',
        type: 'array<string>',
        required: true,
        description: "List of stock ticker symbols to compare (e.g., ['BBCA', 'BMRI'] or ['AAPL', 'MSFT'])."
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
    description: 'Retrieves key financial multiples and fundamental metrics: Trailing P/E, Forward P/E, PBV, ROE, EPS, Free Cash Flow, Dividend Yield, and Market Cap.',
    parameters: [
      {
        name: 'ticker_or_name',
        type: 'string',
        required: true,
        description: "Stock ticker symbol or company name (e.g., 'BBCA', 'TLKM', 'AAPL')."
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
    description: "Searches stocks by company name, brand alias, or ticker symbol (e.g. 'micron', 'apple', 'bca'). Returns full quote information for top matching stocks.",
    parameters: [
      {
        name: 'query',
        type: 'string',
        required: true,
        description: 'Company name or search query.'
      },
      {
        name: 'limit',
        type: 'integer',
        required: false,
        description: 'Search results limit (default: 5).'
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
    description: 'Retrieves top market gainers, losers, and benchmark index performance (IHSG).',
    parameters: [
      {
        name: 'mover_type',
        type: 'string',
        required: false,
        description: "'gainers' for top gainers or 'losers' for top losers (default: 'gainers')."
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
    description: "Retrieves recent financial news articles specifically related to stocks in the user's active portfolio holdings.",
    parameters: [
      {
        name: 'user_id',
        type: 'string',
        required: false,
        description: "User ID (default: 'default_user')."
      },
      {
        name: 'ticker',
        type: 'string',
        required: false,
        description: 'Optional filter for specific ticker symbol.'
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
    description: 'Performs quantitative technical analysis and trend assessment for a stock ticker. Calculates moving averages (MA20, MA50, MA200), Golden Cross vs Death Cross breakout signals, RSI 14 momentum, and dynamic support & resistance levels from historical warehouse data.',
    parameters: [
      {
        name: 'ticker',
        type: 'string',
        required: true,
        description: "Stock ticker symbol (e.g., 'BBCA', 'NVDA', 'TLKM', 'MU')."
      },
      {
        name: 'timeframe',
        type: 'string',
        required: false,
        description: "Technical analysis timeframe period (default: '3M')."
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
