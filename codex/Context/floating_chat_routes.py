"""
src/api/floating_chat_routes.py
Persistent floating chat — context snapshot + message endpoint.

GET  /api/floatchat/context   — DB-only, no AI. Loads once per chat session.
POST /api/floatchat/message   — AI chat using cached context string from frontend.
"""

from __future__ import annotations
import base64
from datetime import datetime, timezone
import hashlib
from io import BytesIO
import json
import logging
import uuid
from typing import Any, Optional

import anthropic
from cryptography.fernet import Fernet, InvalidToken
from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

logger = logging.getLogger("journal")

ANTHROPIC_IMAGE_MAX_BASE64_BYTES = 5 * 1024 * 1024
ANTHROPIC_IMAGE_TARGET_BASE64_BYTES = 4_800_000
ANTHROPIC_IMAGE_MAX_DIMENSION = 1568
SAGE_VISION_MODEL = "claude-sonnet-4-6"
DEFAULT_SAGE_MAX_TOKENS = 1400
MIN_SAGE_MAX_TOKENS = 200
MAX_SAGE_MAX_TOKENS = 2500
MAX_SAVED_CHAT_MESSAGES = 200
MAX_SAVED_CHAT_CONTEXT_CHARS = 120_000
MAX_SAVED_CHAT_CONTENT_CHARS = 80_000


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
    max_tokens: int = Field(
        default=DEFAULT_SAGE_MAX_TOKENS,
        ge=MIN_SAGE_MAX_TOKENS,
        le=MAX_SAGE_MAX_TOKENS,
    )
    images: list[ImageAttachment] = Field(default_factory=list)            # top-level shorthand
    image_attachments: list[ImageAttachment] = Field(default_factory=list) # alternate key iOS may send


class SavedChatMessage(BaseModel):
    role: str
    content: str
    actions: list[dict[str, Any]] = Field(default_factory=list)
    attachments: list[dict[str, Any]] = Field(default_factory=list)


class SavedChatRequest(BaseModel):
    title: Optional[str] = None
    context_string: str = ""
    messages: list[SavedChatMessage] = Field(default_factory=list)
    web_search_enabled: bool = False


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _collapse_saved_text(value: str, limit: int) -> str:
    collapsed = " ".join((value or "").split()).strip()
    if len(collapsed) <= limit:
        return collapsed
    return collapsed[: max(0, limit - 1)].rstrip() + "…"


def _saved_chat_cipher(user_id: int) -> Fernet:
    from src.auth.auth_service import JWT_SECRET

    seed = f"{JWT_SECRET}:floatchat-saved:{user_id}".encode("utf-8")
    key = base64.urlsafe_b64encode(hashlib.sha256(seed).digest())
    return Fernet(key)


def _encrypt_saved_value(user_id: int, value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return _saved_chat_cipher(user_id).encrypt(raw).decode("ascii")


def _decrypt_saved_value(user_id: int, token: str, fallback: Any) -> Any:
    try:
        raw = _saved_chat_cipher(user_id).decrypt((token or "").encode("ascii"))
        return json.loads(raw.decode("utf-8"))
    except (InvalidToken, ValueError, TypeError, json.JSONDecodeError):
        return fallback


def _normalize_saved_messages(messages: list[SavedChatMessage]) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for message in messages[:MAX_SAVED_CHAT_MESSAGES]:
        role = (message.role or "").strip()
        if role not in {"user", "assistant"}:
            continue
        content = (message.content or "")[:MAX_SAVED_CHAT_CONTENT_CHARS]
        if not content.strip():
            continue
        normalized.append({
            "role": role,
            "content": content,
            "actions": message.actions if isinstance(message.actions, list) else [],
            "attachments": message.attachments if isinstance(message.attachments, list) else [],
        })
    return normalized


def _derive_saved_title(messages: list[dict[str, Any]], explicit_title: Optional[str]) -> str:
    explicit = (explicit_title or "").strip()
    if explicit:
        return _collapse_saved_text(explicit, 80)
    for message in messages:
        if message.get("role") == "user":
            content = str(message.get("content") or "").strip()
            if content:
                return _collapse_saved_text(content, 80)
    return "Saved Sage conversation"


def _derive_saved_preview(messages: list[dict[str, Any]]) -> str:
    for message in reversed(messages):
        content = str(message.get("content") or "").strip()
        if content:
            return _collapse_saved_text(content, 180)
    return "No preview available."


def _ensure_saved_chat_table(conn) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS floatchat_saved_conversations (
            id TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            title_enc TEXT NOT NULL,
            preview_enc TEXT NOT NULL,
            context_enc TEXT NOT NULL,
            messages_enc TEXT NOT NULL,
            message_count INTEGER NOT NULL DEFAULT 0,
            web_search_enabled INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_floatchat_saved_user_updated
        ON floatchat_saved_conversations(user_id, updated_at DESC)
        """
    )


def _saved_chat_row_response(user_id: int, row, include_detail: bool = False) -> dict[str, Any]:
    title = _decrypt_saved_value(user_id, row["title_enc"], "Saved Sage conversation")
    preview = _decrypt_saved_value(user_id, row["preview_enc"], "")
    result = {
        "id": row["id"],
        "title": str(title or "Saved Sage conversation"),
        "preview": str(preview or ""),
        "message_count": int(row["message_count"] or 0),
        "web_search_enabled": bool(row["web_search_enabled"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "encrypted_at_rest": True,
    }
    if include_detail:
        result["context_string"] = str(_decrypt_saved_value(user_id, row["context_enc"], "") or "")
        messages = _decrypt_saved_value(user_id, row["messages_enc"], [])
        result["messages"] = messages if isinstance(messages, list) else []
    return result


def _normalize_image_for_anthropic(
    *,
    raw_b64: str,
    media_type: str,
    filename: str,
) -> tuple[str, str]:
    """
    Resize/recompress image payloads so Anthropic vision requests stay below
    Anthropic's 5 MB base64 image-source limit.
    """
    if "," in raw_b64:
        raw_b64 = raw_b64.split(",", 1)[1]

    try:
        image_bytes = base64.b64decode(raw_b64, validate=False)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image base64 for {filename or 'attachment'}: {e}")

    if len(raw_b64.encode("ascii", errors="ignore")) <= ANTHROPIC_IMAGE_TARGET_BASE64_BYTES:
        return media_type, raw_b64

    try:
        from PIL import Image, ImageOps
    except Exception as e:
        raise HTTPException(
            status_code=413,
            detail=(
                "Image is too large for Claude vision and the server cannot resize it "
                f"because Pillow is not installed: {e}"
            ),
        )

    try:
        with Image.open(BytesIO(image_bytes)) as opened:
            try:
                opened.seek(0)
            except Exception:
                pass
            image = ImageOps.exif_transpose(opened).copy()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read image {filename or 'attachment'}: {e}")

    image.thumbnail(
        (ANTHROPIC_IMAGE_MAX_DIMENSION, ANTHROPIC_IMAGE_MAX_DIMENSION),
        Image.Resampling.LANCZOS,
    )

    if image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info):
        flattened = Image.new("RGB", image.size, (255, 255, 255))
        flattened.paste(image.convert("RGBA"), mask=image.convert("RGBA").split()[-1])
        image = flattened
    elif image.mode != "RGB":
        image = image.convert("RGB")

    resized_bytes = b""
    for quality in (85, 80, 75, 70, 65, 60, 55):
        out = BytesIO()
        image.save(out, format="JPEG", quality=quality, optimize=True, progressive=True)
        resized_bytes = out.getvalue()
        if len(base64.b64encode(resized_bytes)) <= ANTHROPIC_IMAGE_TARGET_BASE64_BYTES:
            break

    attempts = 0
    while len(base64.b64encode(resized_bytes)) > ANTHROPIC_IMAGE_TARGET_BASE64_BYTES and attempts < 8:
        attempts += 1
        next_size = (
            max(1, int(image.width * 0.85)),
            max(1, int(image.height * 0.85)),
        )
        image = image.resize(next_size, Image.Resampling.LANCZOS)
        out = BytesIO()
        image.save(out, format="JPEG", quality=75, optimize=True, progressive=True)
        resized_bytes = out.getvalue()

    resized_b64 = base64.b64encode(resized_bytes).decode("ascii")
    if len(resized_b64.encode("ascii")) > ANTHROPIC_IMAGE_MAX_BASE64_BYTES:
        raise HTTPException(
            status_code=413,
            detail=(
                f"Image remains too large after server resize: "
                f"{len(resized_b64.encode('ascii'))} base64 bytes > "
                f"{ANTHROPIC_IMAGE_MAX_BASE64_BYTES} bytes"
            ),
        )

    logger.info(
        "[floatchat/message] resized image %s from %s bytes to %s bytes",
        filename or "attachment",
        len(image_bytes),
        len(resized_bytes),
    )
    return "image/jpeg", resized_b64


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

        user_id = int(current_user["id"])
        conn = get_db()
        try:
            _ensure_saved_chat_table(conn)
            rows = conn.execute(
                """
                SELECT id, user_id, title_enc, preview_enc, context_enc,
                       messages_enc, message_count, web_search_enabled,
                       created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE user_id = ?
                ORDER BY updated_at DESC
                """,
                (user_id,),
            ).fetchall()
            return [_saved_chat_row_response(user_id, row) for row in rows]
        finally:
            conn.close()

    @app.get("/api/floatchat/saved/{conversation_id}")
    async def get_saved_chat(conversation_id: str, current_user: dict = Depends(require_any_user)):
        from src.auth.auth_db import get_db

        user_id = int(current_user["id"])
        conn = get_db()
        try:
            _ensure_saved_chat_table(conn)
            row = conn.execute(
                """
                SELECT id, user_id, title_enc, preview_enc, context_enc,
                       messages_enc, message_count, web_search_enabled,
                       created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Saved conversation not found.")
            return _saved_chat_row_response(user_id, row, include_detail=True)
        finally:
            conn.close()

    @app.post("/api/floatchat/saved")
    async def create_saved_chat(body: SavedChatRequest, current_user: dict = Depends(require_any_user)):
        from src.auth.auth_db import get_db

        user_id = int(current_user["id"])
        messages = _normalize_saved_messages(body.messages)
        if not messages:
            raise HTTPException(status_code=400, detail="No messages provided.")

        now = _utc_now_iso()
        conversation_id = uuid.uuid4().hex
        title = _derive_saved_title(messages, body.title)
        preview = _derive_saved_preview(messages)
        context_string = (body.context_string or "")[:MAX_SAVED_CHAT_CONTEXT_CHARS]

        conn = get_db()
        try:
            _ensure_saved_chat_table(conn)
            conn.execute(
                """
                INSERT INTO floatchat_saved_conversations (
                    id, user_id, title_enc, preview_enc, context_enc,
                    messages_enc, message_count, web_search_enabled,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    conversation_id,
                    user_id,
                    _encrypt_saved_value(user_id, title),
                    _encrypt_saved_value(user_id, preview),
                    _encrypt_saved_value(user_id, context_string),
                    _encrypt_saved_value(user_id, messages),
                    len(messages),
                    1 if body.web_search_enabled else 0,
                    now,
                    now,
                ),
            )
            conn.commit()
            row = conn.execute(
                """
                SELECT id, user_id, title_enc, preview_enc, context_enc,
                       messages_enc, message_count, web_search_enabled,
                       created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            return _saved_chat_row_response(user_id, row, include_detail=True)
        finally:
            conn.close()

    @app.put("/api/floatchat/saved/{conversation_id}")
    async def update_saved_chat(
        conversation_id: str,
        body: SavedChatRequest,
        current_user: dict = Depends(require_any_user),
    ):
        from src.auth.auth_db import get_db

        user_id = int(current_user["id"])
        messages = _normalize_saved_messages(body.messages)
        if not messages:
            raise HTTPException(status_code=400, detail="No messages provided.")

        now = _utc_now_iso()
        title = _derive_saved_title(messages, body.title)
        preview = _derive_saved_preview(messages)
        context_string = (body.context_string or "")[:MAX_SAVED_CHAT_CONTEXT_CHARS]

        conn = get_db()
        try:
            _ensure_saved_chat_table(conn)
            existing = conn.execute(
                "SELECT id FROM floatchat_saved_conversations WHERE id = ? AND user_id = ?",
                (conversation_id, user_id),
            ).fetchone()
            if not existing:
                raise HTTPException(status_code=404, detail="Saved conversation not found.")
            conn.execute(
                """
                UPDATE floatchat_saved_conversations
                SET title_enc = ?,
                    preview_enc = ?,
                    context_enc = ?,
                    messages_enc = ?,
                    message_count = ?,
                    web_search_enabled = ?,
                    updated_at = ?
                WHERE id = ? AND user_id = ?
                """,
                (
                    _encrypt_saved_value(user_id, title),
                    _encrypt_saved_value(user_id, preview),
                    _encrypt_saved_value(user_id, context_string),
                    _encrypt_saved_value(user_id, messages),
                    len(messages),
                    1 if body.web_search_enabled else 0,
                    now,
                    conversation_id,
                    user_id,
                ),
            )
            conn.commit()
            row = conn.execute(
                """
                SELECT id, user_id, title_enc, preview_enc, context_enc,
                       messages_enc, message_count, web_search_enabled,
                       created_at, updated_at
                FROM floatchat_saved_conversations
                WHERE id = ? AND user_id = ?
                """,
                (conversation_id, user_id),
            ).fetchone()
            return _saved_chat_row_response(user_id, row, include_detail=True)
        finally:
            conn.close()

    @app.post("/api/floatchat/saved/{conversation_id}")
    async def upsert_saved_chat_legacy_post(
        conversation_id: str,
        body: SavedChatRequest,
        current_user: dict = Depends(require_any_user),
    ):
        return await update_saved_chat(conversation_id, body, current_user)

    @app.delete("/api/floatchat/saved/{conversation_id}")
    async def delete_saved_chat(conversation_id: str, current_user: dict = Depends(require_any_user)):
        from src.auth.auth_db import get_db

        user_id = int(current_user["id"])
        conn = get_db()
        try:
            _ensure_saved_chat_table(conn)
            cur = conn.execute(
                "DELETE FROM floatchat_saved_conversations WHERE id = ? AND user_id = ?",
                (conversation_id, user_id),
            )
            conn.commit()
            if cur.rowcount < 1:
                raise HTTPException(status_code=404, detail="Saved conversation not found.")
            return {"message": "Saved conversation deleted."}
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
        requested_max_tokens = max(
            MIN_SAGE_MAX_TOKENS,
            min(body.max_tokens, MAX_SAGE_MAX_TOKENS),
        )

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
            "- Default to concise answers, but go deeper when the question clearly needs it.\n"
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
                media_type, raw_b64 = _normalize_image_for_anthropic(
                    raw_b64=img.data_base64,
                    media_type=img.media_type,
                    filename=img.filename,
                )
                last_content.append({
                    "type": "image",
                    "source": {
                        "type":       "base64",
                        "media_type": media_type,
                        "data":       raw_b64,
                    },
                })
            last_content.append({
                "type": "text",
                "text": last_text.strip() or "Please describe what you see in the attached image.",
            })
            messages_payload.append({"role": last_msg.role, "content": last_content})
        else:
            messages_payload.append({"role": last_msg.role, "content": last_text})

        # Anthropic rejects message arrays that begin with an assistant turn.
        # The UI has a hidden session-start prompt, so the first visible turn can
        # otherwise look like [assistant greeting, user image question].
        while messages_payload and messages_payload[0].get("role") != "user":
            dropped = messages_payload.pop(0)
            logger.info(
                "[floatchat/message] dropping leading %s message before Anthropic call",
                dropped.get("role"),
            )
        if not messages_payload:
            fallback_content = last_content if all_images else (last_text.strip() or "Hello")
            messages_payload.append({"role": "user", "content": fallback_content})

        try:
            if all_images:
                # Vision path — call Anthropic directly so we can pass content blocks.
                # Use the same per-user key source as the rest of the app.
                from src.api.ai_client import get_anthropic_key
                api_key = get_anthropic_key(user_id)
                if not api_key:
                    raise RuntimeError("No Anthropic API key configured for this user.")

                client = anthropic.Anthropic(api_key=api_key)
                msg    = client.messages.create(
                    model=SAGE_VISION_MODEL,
                    max_tokens=requested_max_tokens,
                    system=system_prompt,
                    messages=messages_payload,
                )
                raw_response = "".join(
                    getattr(block, "text", "")
                    for block in (msg.content or [])
                    if getattr(block, "type", None) == "text"
                )
            else:
                # Text-only path — use the standard abstraction unchanged
                from src.api.ai_client import create_message
                raw_response = create_message(
                    user_id=user_id,
                    system=system_prompt,
                    user_prompt=last_text,
                    max_tokens=requested_max_tokens,
                    call_type="floating_chat",
                )
        except Exception as e:
            logger.exception("[floatchat/message] AI call failed for user %s", user_id)
            raise HTTPException(
                status_code=500,
                detail=f"AI call failed: {type(e).__name__}: {str(e)[:300]}"
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
