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
      'What is my total portfolio net worth?',
      'Summary of my current portfolio balance',
      'Is my portfolio in profit or loss today?'
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
      'How many shares of BBCA do I currently hold?',
      'Check my Micron (MU) holding position',
      'Show all stock positions in my portfolio'
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
      'How is my portfolio performing this week?',
      'What is my year-to-date (YTD) portfolio return?',
      'Check my monthly portfolio performance'
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
      'What is the sector allocation of my portfolio?',
      'What percentage of my portfolio is in technology stocks?',
      'Show my largest stock holdings by weighting'
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
      'Which stock gained the most in my portfolio today?',
      'Who are the top losers in my portfolio?',
      'Show significant moving stocks in my portfolio today'
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
      'What is the floating profit on my BBCA shares?',
      'Calculate total unrealized P&L for my entire portfolio',
      'Am I in profit on my MU holding?'
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
      'What is the current stock price of BBCA?',
      'Check real-time stock price for Apple (AAPL)',
      'How is GOTO moving today?'
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
        description: 'The stock ticker symbol.'
      },
      {
        name: 'period',
        type: 'string',
        required: true,
        description: "Time period: 'daily', 'weekly', 'monthly', 'ytd', 'yearly', or 'all'."
      }
    ],
    example_queries: [
      'How has BBCA performed over the past 1 year?',
      'What is NVDA stock return over the past month?',
      'Show 1-year historical performance breakdown for ASII'
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
      'Why did Micron (MU) surge sharply yesterday?',
      'What is the outlook for NVDA and data center competition?',
      'Analyze latest news sentiment and earnings catalysts for BBRI'
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
      'Search acquisition news or corporate actions for major banks',
      'SEC filings regarding Nvidia AI capital expenditure',
      'Semiconductor industry trade policy and tariff sentiment'
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
    description: 'Calculates estimated risk level and projected return impact of macroeconomic events (e.g., Fed interest rate hikes, inflation, currency devaluation, recession) against the user\'s specific stock portfolio holdings.',
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
      'How will a 50 bps Fed rate hike impact my portfolio?',
      'Simulate currency depreciation impact on my holdings',
      'What is the effect of an inflation surge on banking and consumer sectors?'
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
      'Analyze sentiment for Apple quarterly earnings release',
      'Impact of rising coal prices on energy sector equities',
      'Market sentiment on potential interest rate cuts'
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
      'Compare BBCA and BMRI based on valuation multiples',
      'Tech sector comparison: NVDA vs AMD vs INTC',
      'Compare dividend yield between ASII, BBRI, and TLKM'
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
      'What is the P/E ratio and PBV of BBCA?',
      'Check key financial fundamental ratios for TLKM',
      'What is the dividend yield of ASII?'
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
      'Search ticker symbol for Bank Central Asia',
      'Find stock ticker for memory chipmaker Micron',
      'Search for electric vehicle and battery manufacturers'
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
      'Show top market gainers today',
      'Which stocks are declining the most today?',
      'What is the current performance of the benchmark index?'
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
      'What are the most relevant news headlines for my portfolio today?',
      'Show news sentiment across the stocks I currently own'
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
      'What is the technical analysis trend for BBCA right now?',
      'Is NVDA forming a Golden Cross breakout signal?',
      'Check support, resistance levels, and RSI for TLKM'
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
