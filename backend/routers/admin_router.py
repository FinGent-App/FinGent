import logging
from typing import Optional, Dict, Any, List
from fastapi import APIRouter, HTTPException, Query, BackgroundTasks
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from services.admin_service import (
    subscribe_admin_events,
    record_agent_log,
    get_recent_logs,
    get_llmops_analytics,
    get_tables_overview,
    get_table_data,
    delete_table_row,
    get_feeds_status,
    broadcast_admin_event,
    get_app_tools
)
from services.rss_ingestion_service import sync_all_rss_feeds

logger = logging.getLogger("FinGent.AdminRouter")

admin_router = APIRouter()

# ==============================================================================
# 1. Real-Time Server-Sent Events (SSE) Stream
# ==============================================================================

@admin_router.get("/events")
async def sse_admin_events():
    """
    Subscribes the web dashboard to real-time events via Server-Sent Events (SSE).
    Emits live agent traces, tool calls, token stats, and ingestion updates.
    """
    return StreamingResponse(
        subscribe_admin_events(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


# ==============================================================================
# 2. LLMOps & Tool Decision Trace Endpoints
# ==============================================================================

@admin_router.get("/analytics")
async def get_analytics():
    """Returns aggregated LLMOps metrics: token consumption, estimated cost, and tool calls."""
    try:
        return await get_llmops_analytics()
    except Exception as e:
        logger.error("Failed to retrieve LLMOps analytics: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@admin_router.get("/logs")
async def get_logs(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0)
):
    """Returns chronologically ordered query traces for the decision flowchart."""
    try:
        logs = await get_recent_logs(limit, offset)
        return {"count": len(logs), "logs": logs}
    except Exception as e:
        logger.error("Failed to retrieve agent query logs: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@admin_router.get("/tools")
async def get_tools():
    """
    Returns the complete list and metadata of all tools provided in FinGent:
    On-Device (Apple FoundationModels), Cloud Analyst (Gemini + RAG), and MCP Remote Tools.
    """
    try:
        return get_app_tools()
    except Exception as e:
        logger.error("Failed to retrieve app tools catalog: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))



class AgentTracePayload(BaseModel):
    user_id: str = "default_user"
    prompt: str
    selected_tools: List[str] = Field(default_factory=list)
    tool_arguments: Dict[str, Any] = Field(default_factory=dict)
    tool_output: Optional[str] = None
    final_answer: Optional[str] = None
    citations: Optional[List[Dict[str, Any]]] = None
    market_type: str = "GLOBAL"
    model_name: str = "gemini-3.6-flash"
    prompt_tokens: int = 0
    completion_tokens: int = 0
    latency_ms: int = 0
    relevance_score: float = 0.95
    status: str = "SUCCESS"
    error_message: Optional[str] = None


@admin_router.post("/trace")
async def record_trace(payload: AgentTracePayload):
    """
    Called by iOS or backend tools to log tool execution decisions and broadcast live to web.
    """
    try:
        res = await record_agent_log(
            user_id=payload.user_id,
            prompt=payload.prompt,
            selected_tools=payload.selected_tools,
            tool_arguments=payload.tool_arguments,
            tool_output=payload.tool_output,
            final_answer=payload.final_answer,
            citations=payload.citations,
            market_type=payload.market_type,
            model_name=payload.model_name,
            prompt_tokens=payload.prompt_tokens,
            completion_tokens=payload.completion_tokens,
            latency_ms=payload.latency_ms,
            relevance_score=payload.relevance_score,
            status=payload.status,
            error_message=payload.error_message
        )
        return {"status": "recorded", "id": res.get("id")}
    except Exception as e:
        logger.error("Failed to record agent trace: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# 3. PostgreSQL Table Explorer (Mini-Supabase Viewer)
# ==============================================================================

@admin_router.get("/tables")
async def list_tables():
    """Lists all database tables with total row counts for the left sidebar."""
    try:
        tables = await get_tables_overview()
        return {"tables": tables}
    except Exception as e:
        logger.error("Failed to list tables: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@admin_router.get("/tables/{table_name}")
async def inspect_table(
    table_name: str,
    page: int = Query(1, ge=1),
    limit: int = Query(25, ge=5, le=100),
    search: Optional[str] = Query(None),
    sort_by: Optional[str] = Query(None),
    sort_dir: str = Query("DESC")
):
    """Retrieves paginated data from any PostgreSQL table with search & sorting."""
    try:
        data = await get_table_data(
            table_name=table_name,
            page=page,
            limit=limit,
            search=search,
            sort_by=sort_by,
            sort_dir=sort_dir
        )
        return data
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        logger.error("Failed to fetch table data for %s: %s", table_name, str(e))
        raise HTTPException(status_code=500, detail=str(e))


@admin_router.delete("/tables/{table_name}/{row_id}")
async def remove_row(table_name: str, row_id: str):
    """Deletes a single row from a database table."""
    try:
        success = await delete_table_row(table_name, row_id)
        if not success:
            raise HTTPException(status_code=400, detail="Failed to delete row. Check if ID exists.")
        return {"status": "deleted", "table": table_name, "id": row_id}
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        logger.error("Delete error for %s / %s: %s", table_name, row_id, str(e))
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# 4. RSS Feeds Health & Manual Sync
# ==============================================================================

@admin_router.get("/feeds/status")
async def feeds_health():
    """Returns the real-time status and DB article counts of all 12 RSS feeds."""
    try:
        return {"feeds": await get_feeds_status()}
    except Exception as e:
        logger.error("Failed to get feeds status: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@admin_router.post("/feeds/sync")
async def trigger_rss_sync(background_tasks: BackgroundTasks):
    """Triggers an immediate background synchronization across all 12 RSS providers."""
    async def _run_sync():
        count = await sync_all_rss_feeds()
        await broadcast_admin_event("rss_synced", {"count": count})

    background_tasks.add_task(_run_sync)
    return {"status": "sync_started", "message": "All 12 RSS feeds are synchronizing in the background."}
