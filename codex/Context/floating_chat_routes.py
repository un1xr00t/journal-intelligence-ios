"""
src/api/floating_chat_routes.py
Persistent floating chat — context snapshot + message endpoint.

GET  /api/floatchat/context   — DB-only, no AI. Loads once per chat session.
POST /api/floatchat/message   — AI chat using cached context string from frontend.
"""

from __future__ import annotations
import anthropic
import json
import logging
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

from fastapi import Depends, HTTPException
from pydantic import BaseModel

logger = logging.getLogger("journal")


class ChatMessage(BaseModel):
    role: str   # "user" | "assistant"
    content: str


class ImageAttachment(BaseModel):
    filename: str = ""
    media_type: str = "image/jpeg"   # image/jpeg | image/png | image/gif | image/webp
    data_base64: str                  # raw base64, no data-URI prefix


class ChatRequest(BaseModel):
    messages: list[ChatMessage]
    context_string: str                           # cached from /context
    images: list[ImageAttachment] = []            # top-level shorthand
    image_attachments: list[ImageAttachment] = [] # alternate key iOS may send
    enable_web_search: bool = False


class SavedChatMessage(BaseModel):
    role: str
    content: str
    actions: list[dict] = []


class SaveChatRequest(BaseModel):
    title: Optional[str] = None
    context_string: str = ""
    messages: list[SavedChatMessage]
    web_search_enabled: bool = False


def _ensure_saved_chat_tables(conn) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS floatchat_saved_conversations (
            id TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            preview TEXT NOT NULL,
            context_string TEXT,
            message_count INTEGER NOT NULL DEFAULT 0,
            web_search_enabled INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS floatchat_saved_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            message_order INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            actions_json TEXT,
            created_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_floatchat_saved_conversations_user_updated
        ON floatchat_saved_conversations (user_id, updated_at DESC)
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_floatchat_saved_messages_conversation_order
        ON floatchat_saved_messages (conversation_id, message_order)
        """
    )
    conn.commit()


def _collapse_text(value: Optional[str], *, limit: int) -> str:
    text = " ".join((value or "").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def _derive_saved_chat_title(messages: list[SavedChatMessage], explicit: Optional[str]) -> str:
    if explicit and explicit.strip():
        return _collapse_text(explicit.strip(), limit=80)

    for message in messages:
        if message.role == "user" and message.content.strip():
            return _collapse_text(message.content.strip(), limit=80)

    for message in messages:
        if message.content.strip():
            return _collapse_text(message.content.strip(), limit=80)

    return "Saved Sage conversation"


def _derive_saved_chat_preview(messages: list[SavedChatMessage]) -> str:
    for message in reversed(messages):
        if message.role == "assistant" and message.content.strip():
            return _collapse_text(message.content.strip(), limit=180)

    for message in reversed(messages):
        if message.content.strip():
            return _collapse_text(message.content.strip(), limit=180)

    return "No preview available."


def _serialize_saved_chat_summary(row) -> dict:
    return {
        "id": row["id"],
        "title": row["title"],
        "preview": row["preview"],
        "message_count": row["message_count"],
        "web_search_enabled": bool(row["web_search_enabled"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def _serialize_saved_chat_message(row) -> dict:
    try:
        actions = json.loads(row["actions_json"] or "[]")
    except Exception:
        actions = []

    return {
        "role": row["role"],
        "content": row["content"],
        "actions": actions if isinstance(actions, list) else [],
    }


def _save_conversation_snapshot(
    conn,
    *,
    user_id: int,
    conversation_id: str,
    title: str,
    preview: str,
    context_string: str,
    web_search_enabled: bool,
    messages: list[SavedChatMessage],
    existing: bool,
) -> None:
    now = datetime.now(timezone.utc).isoformat()
    message_count = len(messages)

    if existing:
        conn.execute(
            """
            UPDATE floatchat_saved_conversations
            SET title = ?, preview = ?, context_string = ?, message_count = ?,
                web_search_enabled = ?, updated_at = ?
            WHERE id = ? AND user_id = ?
            """,
            (
                title,
                preview,
                context_string,
                message_count,
                1 if web_search_enabled else 0,
                now,
                conversation_id,
                user_id,
            ),
        )
        conn.execute(
            """
            DELETE FROM floatchat_saved_messages
            WHERE conversation_id = ? AND user_id = ?
            """,
            (conversation_id, user_id),
        )
    else:
        conn.execute(
            """
            INSERT INTO floatchat_saved_conversations (
                id, user_id, title, preview, context_string, message_count,
                web_search_enabled, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                conversation_id,
                user_id,
                title,
                preview,
                context_string,
                message_count,
                1 if web_search_enabled else 0,
                now,
                now,
            ),
        )

    for index, message in enumerate(messages):
        conn.execute(
            """
            INSERT INTO floatchat_saved_messages (
                conversation_id, user_id, message_order, role, content,
                actions_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                conversation_id,
                user_id,
                index,
                message.role,
                message.content,
                json.dumps(message.actions or []),
                now,
            ),
        )

    conn.commit()


def register_floating_chat_routes(app, require_any_user):

    # ── GET /api/floatchat/context ────────────────────────────────────────────
    @app.get("/api/floatchat/context")
    async def get_chat_context(current_user: dict = Depends(require_any_user)):
        """
        Assembles a compact context snapshot from DB + files — no AI calls.
        Frontend caches this string for the entire chat session.
        """
        from src.auth.auth_db import get_db
        from src.api.onboarding_routes import load_user_memory, build_memory_context_string

        user_id = current_user["id"]
        conn = get_db()
        parts = []
        entry_count = 0

        try:
            # ── User memory / profile (file-based) ───────────────────────────
            memory = load_user_memory(user_id)
            mem_ctx = build_memory_context_string(memory)
            if mem_ctx:
                parts.append(mem_ctx)

            # ── Master summary ────────────────────────────────────────────────
            ms = conn.execute(
                """
                SELECT current_state, active_threads, overall_arc, key_themes, last_entry_date
                FROM master_summaries
                WHERE user_id = ?
                ORDER BY version DESC LIMIT 1
                """,
                (user_id,)
            ).fetchone()

            if ms:
                ms_parts = []
                if ms["current_state"]:
                    ms_parts.append(f"Current state: {ms['current_state']}")
                if ms["overall_arc"]:
                    ms_parts.append(f"Overall arc: {ms['overall_arc']}")
                try:
                    threads = json.loads(ms["active_threads"] or "[]")
                    if threads:
                        ms_parts.append("Open threads:\n" + "\n".join(f"  {t}" for t in threads[:8]))
                except Exception:
                    pass
                try:
                    themes = json.loads(ms["key_themes"] or "[]")
                    if themes:
                        ms_parts.append("Key themes: " + ", ".join(themes[:6]))
                except Exception:
                    pass
                if ms_parts:
                    parts.append("=== NARRATIVE SUMMARY ===\n" + "\n".join(ms_parts))

            # ── Recent entry summaries ────────────────────────────────────────
            recent = conn.execute(
                """
                SELECT e.entry_date, ds.summary_text, ds.mood_label, ds.severity
                FROM entries e
                JOIN derived_summaries ds ON ds.entry_id = e.id
                WHERE e.user_id = ? AND e.is_current = 1
                  AND ds.summary_text IS NOT NULL
                ORDER BY e.entry_date DESC
                LIMIT 15
                """,
                (user_id,)
            ).fetchall()

            if recent:
                lines = []
                for r in recent:
                    mood = f" [{r['mood_label']}]" if r['mood_label'] else ""
                    sev  = f" sev={r['severity']:.1f}" if r['severity'] else ""
                    lines.append(f"{r['entry_date']}{mood}{sev}: {r['summary_text']}")
                parts.append("=== RECENT JOURNAL ENTRIES ===\n" + "\n".join(lines))

            # ── Entry stats ───────────────────────────────────────────────────
            stats = conn.execute(
                """
                SELECT COUNT(*) as cnt, MIN(entry_date) as first, MAX(entry_date) as last
                FROM entries WHERE user_id = ? AND is_current = 1
                """,
                (user_id,)
            ).fetchone()

            if stats and stats["cnt"]:
                entry_count = stats["cnt"]
                parts.append(f"=== JOURNAL STATS ===\nTotal entries: {entry_count} | First: {stats['first']} | Latest: {stats['last']}")

            # ── Active alerts / patterns ──────────────────────────────────────
            alerts = conn.execute(
                """
                SELECT alert_type, description, priority_score
                FROM alerts
                WHERE user_id = ? AND acknowledged = 0
                ORDER BY priority_score DESC LIMIT 8
                """,
                (user_id,)
            ).fetchall()

            if alerts:
                lines = [
                    f"  [{a['alert_type']}] (priority {a['priority_score']:.1f}): {a['description'][:200]}"
                    for a in alerts
                ]
                parts.append("=== ACTIVE PATTERNS / ALERTS ===\n" + "\n".join(lines))

            # ── Evidence vault summary ────────────────────────────────────────
            evidence = conn.execute(
                """
                SELECT evidence_type, label, quote_text
                FROM evidence
                WHERE user_id = ?
                ORDER BY created_at DESC LIMIT 10
                """,
                (user_id,)
            ).fetchall()

            if evidence:
                lines = [
                    f"  [{e['evidence_type']}] {e['label']}" + (f': "{e["quote_text"][:120]}"' if e['quote_text'] else "")
                    for e in evidence
                ]
                parts.append("=== EVIDENCE VAULT (recent) ===\n" + "\n".join(lines))

            # ── Detective cases ───────────────────────────────────────────────
            cases = conn.execute(
                """
                SELECT title, description, status, updated_at
                FROM detective_cases
                WHERE user_id = ?
                ORDER BY updated_at DESC LIMIT 6
                """,
                (user_id,)
            ).fetchall()

            if cases:
                lines = []
                for c in cases:
                    desc = f": {c['description'][:120]}" if c['description'] else ""
                    lines.append(f"  [{c['status']}] {c['title']}{desc}")
                parts.append("=== DETECTIVE CASES ===\n" + "\n".join(lines))

            # ── Exit plan (corrected schema) ──────────────────────────────────
            try:
                plan = conn.execute(
                    "SELECT id, plan_type, branches, status FROM exit_plans WHERE user_id = ?",
                    (user_id,)
                ).fetchone()

                if plan:
                    plan_id = plan["id"]
                    try:
                        branches = json.loads(plan["branches"]) if plan["branches"] else []
                    except Exception:
                        branches = []

                    phases = conn.execute(
                        "SELECT phase_order, title, status FROM exit_plan_phases WHERE plan_id = ? ORDER BY phase_order",
                        (plan_id,)
                    ).fetchall()

                    tasks = conn.execute(
                        """SELECT t.title, t.status, t.priority, p.title as phase_title
                           FROM exit_plan_tasks t
                           JOIN exit_plan_phases p ON p.id = t.phase_id
                           WHERE t.plan_id = ?
                           ORDER BY p.phase_order, t.priority DESC""",
                        (plan_id,)
                    ).fetchall()

                    doing   = [t for t in tasks if t["status"] == "doing"]
                    next_up = [t for t in tasks if t["status"] == "next"]
                    done    = [t for t in tasks if t["status"] == "done"]
                    backlog = [t for t in tasks if t["status"] == "backlog"]

                    ep_lines = [f"Plan type: {plan['plan_type']} | Branches: {', '.join(branches) if branches else 'general'} | Status: {plan['status']}"]

                    if phases:
                        phase_strs = []
                        for ph in phases:
                            emoji = {"active": "▶", "completed": "✓", "locked": "🔒"}.get(ph["status"], "○")
                            phase_strs.append(f"{emoji} Phase {ph['phase_order']}: {ph['title']} [{ph['status']}]")
                        ep_lines.append("Phases:\n" + "\n".join(f"  {p}" for p in phase_strs))

                    if doing:
                        ep_lines.append("Currently working on: " + "; ".join(t["title"] for t in doing[:3]))
                    if next_up:
                        ep_lines.append("Up next: " + "; ".join(t["title"] for t in next_up[:3]))
                    ep_lines.append(f"Progress: {len(done)} tasks done, {len(backlog)} in backlog")

                    parts.append("=== EXIT PLAN ===\n" + "\n".join(ep_lines))

            except Exception as ep_err:
                logger.warning(f"[floatchat/context] exit plan fetch failed: {ep_err}")

            # ── Contradiction count ───────────────────────────────────────────
            contra = conn.execute(
                "SELECT COUNT(*) as cnt FROM alerts WHERE user_id = ? AND alert_type = 'contradiction' AND acknowledged = 0",
                (user_id,)
            ).fetchone()
            if contra and contra["cnt"]:
                parts.append(f"=== CONTRADICTIONS ===\n{contra['cnt']} unacknowledged contradiction(s) detected in journal.")

        except Exception as e:
            logger.error(f"[floatchat/context] error for user {user_id}: {e}", exc_info=True)
            raise HTTPException(status_code=500, detail=f"Context load failed: {str(e)}")
        finally:
            conn.close()

        context_string = "\n\n".join(parts) if parts else "No journal data loaded yet. Add some entries first."

        return {
            "context_string": context_string,
            "entry_count": entry_count,
        }

    # ── Saved Sage conversations ─────────────────────────────────────────────
    @app.get("/api/floatchat/saved")
    async def list_saved_chats(current_user: dict = Depends(require_any_user)):
        from src.auth.auth_db import get_db

        user_id = current_user["id"]
        conn = get_db()
        try:
            _ensure_saved_chat_tables(conn)
            rows = conn.execute(
                """
                SELECT id, title, preview, message_count, web_search_enabled,
                       created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE user_id = ?
                ORDER BY updated_at DESC
                """,
                (user_id,),
            ).fetchall()
            return [_serialize_saved_chat_summary(row) for row in rows]
        except Exception as e:
            logger.error(
                f"[floatchat/saved:list] error for user {user_id}: {e}",
                exc_info=True,
            )
            raise HTTPException(status_code=500, detail="Failed to load saved conversations.")
        finally:
            conn.close()

    @app.get("/api/floatchat/saved/{conversation_id}")
    async def get_saved_chat(conversation_id: str, current_user: dict = Depends(require_any_user)):
        from src.auth.auth_db import get_db

        user_id = current_user["id"]
        conn = get_db()
        try:
            _ensure_saved_chat_tables(conn)
            row = conn.execute(
                """
                SELECT id, title, preview, context_string, message_count,
                       web_search_enabled, created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Saved conversation not found.")

            message_rows = conn.execute(
                """
                SELECT role, content, actions_json
                FROM floatchat_saved_messages
                WHERE conversation_id = ? AND user_id = ?
                ORDER BY message_order ASC, id ASC
                """,
                (conversation_id, user_id),
            ).fetchall()

            payload = _serialize_saved_chat_summary(row)
            payload["context_string"] = row["context_string"] or ""
            payload["messages"] = [
                _serialize_saved_chat_message(message_row)
                for message_row in message_rows
            ]
            return payload
        except HTTPException:
            raise
        except Exception as e:
            logger.error(
                f"[floatchat/saved:get] error for user {user_id}: {e}",
                exc_info=True,
            )
            raise HTTPException(status_code=500, detail="Failed to load saved conversation.")
        finally:
            conn.close()

    @app.post("/api/floatchat/saved")
    async def create_saved_chat(
        body: SaveChatRequest,
        current_user: dict = Depends(require_any_user),
    ):
        from src.auth.auth_db import get_db

        if not body.messages:
            raise HTTPException(status_code=400, detail="No messages provided.")

        user_id = current_user["id"]
        conn = get_db()
        try:
            _ensure_saved_chat_tables(conn)
            conversation_id = uuid4().hex
            title = _derive_saved_chat_title(body.messages, body.title)
            preview = _derive_saved_chat_preview(body.messages)
            _save_conversation_snapshot(
                conn,
                user_id=user_id,
                conversation_id=conversation_id,
                title=title,
                preview=preview,
                context_string=body.context_string or "",
                web_search_enabled=body.web_search_enabled,
                messages=body.messages,
                existing=False,
            )
            row = conn.execute(
                """
                SELECT id, title, preview, context_string, message_count,
                       web_search_enabled, created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            payload = _serialize_saved_chat_summary(row)
            payload["context_string"] = row["context_string"] or ""
            payload["messages"] = [
                {
                    "role": message.role,
                    "content": message.content,
                    "actions": message.actions or [],
                }
                for message in body.messages
            ]
            return payload
        except HTTPException:
            raise
        except Exception as e:
            logger.error(
                f"[floatchat/saved:create] error for user {user_id}: {e}",
                exc_info=True,
            )
            raise HTTPException(status_code=500, detail="Failed to save conversation.")
        finally:
            conn.close()

    @app.put("/api/floatchat/saved/{conversation_id}")
    async def update_saved_chat(
        conversation_id: str,
        body: SaveChatRequest,
        current_user: dict = Depends(require_any_user),
    ):
        from src.auth.auth_db import get_db

        if not body.messages:
            raise HTTPException(status_code=400, detail="No messages provided.")

        user_id = current_user["id"]
        conn = get_db()
        try:
            _ensure_saved_chat_tables(conn)
            existing_row = conn.execute(
                """
                SELECT id
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            if not existing_row:
                raise HTTPException(status_code=404, detail="Saved conversation not found.")

            title = _derive_saved_chat_title(body.messages, body.title)
            preview = _derive_saved_chat_preview(body.messages)
            _save_conversation_snapshot(
                conn,
                user_id=user_id,
                conversation_id=conversation_id,
                title=title,
                preview=preview,
                context_string=body.context_string or "",
                web_search_enabled=body.web_search_enabled,
                messages=body.messages,
                existing=True,
            )
            row = conn.execute(
                """
                SELECT id, title, preview, context_string, message_count,
                       web_search_enabled, created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            payload = _serialize_saved_chat_summary(row)
            payload["context_string"] = row["context_string"] or ""
            payload["messages"] = [
                {
                    "role": message.role,
                    "content": message.content,
                    "actions": message.actions or [],
                }
                for message in body.messages
            ]
            return payload
        except HTTPException:
            raise
        except Exception as e:
            logger.error(
                f"[floatchat/saved:update] error for user {user_id}: {e}",
                exc_info=True,
            )
            raise HTTPException(status_code=500, detail="Failed to update saved conversation.")
        finally:
            conn.close()

    @app.delete("/api/floatchat/saved/{conversation_id}")
    async def delete_saved_chat(
        conversation_id: str,
        current_user: dict = Depends(require_any_user),
    ):
        from src.auth.auth_db import get_db

        user_id = current_user["id"]
        conn = get_db()
        try:
            _ensure_saved_chat_tables(conn)
            row = conn.execute(
                """
                SELECT id
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Saved conversation not found.")

            conn.execute(
                """
                DELETE FROM floatchat_saved_messages
                WHERE conversation_id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            )
            conn.execute(
                """
                DELETE FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            )
            conn.commit()
            return {"message": "Saved conversation deleted."}
        except HTTPException:
            raise
        except Exception as e:
            logger.error(
                f"[floatchat/saved:delete] error for user {user_id}: {e}",
                exc_info=True,
            )
            raise HTTPException(status_code=500, detail="Failed to delete saved conversation.")
        finally:
            conn.close()

    # ── POST /api/floatchat/message ───────────────────────────────────────────
    @app.post("/api/floatchat/message")
    async def chat_message(body: ChatRequest, current_user: dict = Depends(require_any_user)):
        """
        AI chat using pre-cached context string from the frontend.
        Returns structured JSON with reply + optional action buttons.
        """
        if not body.messages:
            raise HTTPException(status_code=400, detail="No messages provided.")

        user_id = current_user["id"]
        enable_web_search = getattr(body, "enable_web_search", False)

        system_prompt = (
            "You are a deeply perceptive AI embedded inside someone's private journal dashboard. "
            "You have read everything they've written — their entries, patterns, exit plan, evidence, detective cases. "
            "You are not a generic chatbot. You speak like a trusted advisor who knows their full story.\n\n"
            "RESPONSE FORMAT:\n"
            "Write your reply as normal text (markdown ok: **bold**, bullet lists with -).\n"
            "If and ONLY IF a specific tool would genuinely help right now, append an ACTIONS block at the very end:\n"
            "---ACTIONS---\n"
            "/route 🔎 Label for button\n"
            "/route2 ⚔ Another button\n"
            "---END---\n\n"
            "Max 3 action lines. Valid routes: /exit-plan /evidence /detective /war-room /write /patterns /mental-health /people-intel /contradictions /nervous\n"
            "Do NOT include the ACTIONS block if no specific action is needed — most replies won't need it.\n\n"
            "Rules:\n"
            "- Reference specific dates, names, events from context. Be specific, not vague.\n"
            "- Never fabricate. If you don't see it in context, say so.\n"
            "- Speak directly. Like a trusted friend who has read everything.\n"
            "- Keep responses under 200 words unless depth is clearly needed.\n"
            "- If they seem in crisis or danger, acknowledge it directly and include /war-room or /exit-plan action.\n\n"
            "=== YOUR CONTEXT ===\n"
            f"{body.context_string}\n"
            "=== END CONTEXT ==="
        )

        # Cap at last 20 messages
        history = body.messages[-20:]

        # ── Merge both image fields the iOS client might send ─────────────────
        all_images = list(body.images or []) + list(body.image_attachments or [])

        # ── Build Anthropic messages payload ──────────────────────────────────
        # History messages (all except the last) are always text-only.
        messages_payload = [
            {"role": m.role, "content": m.content}
            for m in history[:-1]
        ]

        # The last user message may carry image content blocks.
        last_msg  = history[-1]
        last_text = last_msg.content or ""

        if all_images:
            # Multimodal content block list — images first, then text
            last_content = []
            for img in all_images:
                # Strip data-URI prefix if iOS accidentally includes it
                raw_b64 = img.data_base64
                if "," in raw_b64:
                    raw_b64 = raw_b64.split(",", 1)[1]
                last_content.append({
                    "type": "image",
                    "source": {
                        "type":       "base64",
                        "media_type": img.media_type,
                        "data":       raw_b64,
                    },
                })
            last_content.append({"type": "text", "text": last_text})
            messages_payload.append({"role": last_msg.role, "content": last_content})
        else:
            messages_payload.append({"role": last_msg.role, "content": last_text})

        try:
            if all_images:
                # Vision path — call Anthropic directly so we can pass content blocks
                from src.api.anthropic_helper import get_anthropic_client, get_model
                client = get_anthropic_client(user_id)
                model  = get_model()
                tools = []
                if enable_web_search:
                    tools.append({
                        "type": "web_search_20250305",
                        "name": "web_search",
                    })
                msg    = client.messages.create(
                    model=model,
                    max_tokens=500,
                    system=system_prompt,
                    messages=messages_payload,
                    tools=tools if tools else anthropic.NOT_GIVEN,
                )
                raw_response = " ".join(
                    block.text for block in msg.content if block.type == "text"
                ).strip()
            else:
                # Text-only path — use the standard abstraction unchanged
                if enable_web_search:
                    from src.api.anthropic_helper import get_anthropic_client, get_model
                    client = get_anthropic_client(user_id)
                    model = get_model()
                    tools = [{
                        "type": "web_search_20250305",
                        "name": "web_search",
                    }]
                    msg = client.messages.create(
                        model=model,
                        max_tokens=500,
                        system=system_prompt,
                        messages=messages_payload,
                        tools=tools,
                    )
                    raw_response = " ".join(
                        block.text for block in msg.content if block.type == "text"
                    ).strip()
                else:
                    from src.api.ai_client import create_message
                    raw_response = create_message(
                        user_id=user_id,
                        system=system_prompt,
                        user_prompt=last_text,
                        max_tokens=500,
                        call_type="floating_chat",
                    )
        except Exception as e:
            logger.exception(f"[floatchat/message] AI call failed for user {user_id}")
            raise HTTPException(
                status_code=500,
                detail="AI call failed. Make sure your API key is set in Settings -> AI Preferences."
            )

        # ── Parse delimiter-based response (reliable, no JSON fragility) ─────
        raw = (raw_response or "").strip()
        actions = []

        if "---ACTIONS---" in raw:
            parts_split = raw.split("---ACTIONS---", 1)
            reply = parts_split[0].strip()
            actions_block = parts_split[1].split("---END---")[0].strip()
            for line in actions_block.splitlines():
                line = line.strip()
                if not line:
                    continue
                tokens = line.split(" ", 2)   # route, icon, label
                if len(tokens) >= 3:
                    actions.append({"route": tokens[0], "icon": tokens[1], "label": tokens[2]})
                elif len(tokens) == 2:
                    actions.append({"route": tokens[0], "icon": "→", "label": tokens[1]})
        else:
            reply = raw

        return {"reply": reply, "actions": actions}
