"""Servidor MCP backend (FastMCP) con las MCPs por defecto por cuenta de Jabvox.

Cada tool recibe SIEMPRE el account_id de la cuenta cuyo virtual server la invoca (lo
inyecta ContextForge desde el scoped token), y llama de vuelta a Jabvox por su API con
ese account_id. El aislamiento lo garantiza ContextForge: el scoped token de la cuenta N
solo puede ver/llamar las tools del virtual server de N.

Este es un ESQUELETO funcional para el e2e; adáptalo a tus fuentes de datos reales.
"""
import os
import httpx
from fastmcp import FastMCP

JABVOX_CALLBACK_URL = os.environ.get("JABVOX_CALLBACK_URL", "http://host.docker.internal:3000")

mcp = FastMCP("jabvox-account-mcps")


@mcp.tool()
def jabvox_core_account_summary(account_id: int) -> dict:
    """Resumen de la cuenta Jabvox (conversaciones abiertas, agentes, etc.)."""
    with httpx.Client(base_url=JABVOX_CALLBACK_URL, timeout=15) as c:
        # El account_id lo fija ContextForge desde el scoped token; nunca lo elige el modelo.
        r = c.get(f"/api/v1/accounts/{account_id}/conversations/meta")
        return {"account_id": account_id, "status": r.status_code, "data": _safe_json(r)}


@mcp.tool()
def analytics_db_query(account_id: int, question: str) -> dict:
    """Consulta analítica de solo-lectura sobre la base de datos externa de la cuenta.

    Adapta esto a tu conector real (SQL read-only, warehouse, etc.), SIEMPRE acotado
    por account_id para no cruzar datos entre cuentas.
    """
    return {"account_id": account_id, "question": question,
            "note": "conecta aquí tu DB de analytics (read-only, acotada por account_id)"}


@mcp.tool()
def reports_generate(account_id: int, report: str) -> dict:
    """Genera/recupera un reporte de la cuenta (ventas, CDR, dialer, ...)."""
    return {"account_id": account_id, "report": report,
            "note": "conecta aquí tu generador de reportes por cuenta"}


def _safe_json(resp):
    try:
        return resp.json()
    except Exception:
        return None


if __name__ == "__main__":
    # HTTP transport para que ContextForge lo federe.
    mcp.run(transport="http", host="0.0.0.0", port=9000)
