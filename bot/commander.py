#!/usr/bin/env python3
"""
ChengetAi Deploy — Telegram Bot with Live Ollama Conversation
=============================================================
While DSpace installs, the user can chat with Ollama in natural language.
Ollama reads the live installer logs and answers questions like:
  "How's it going?"       → "Setting up Solr search cores, about 4 min left"
  "What's happening now?" → "DSpace is initialising the database schema"
  "Is there an error?"    → "No errors yet, looking healthy"

Requires:
    pip3 install python-telegram-bot requests
"""

import asyncio
import json
import logging
import os
import sys
import time
from collections import deque
from pathlib import Path

import requests
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

# ═══════════════════════════════════════════════════════════════════
#  CONFIGURATION — edit these two lines before running
# ═══════════════════════════════════════════════════════════════════
BOT_TOKEN     = "YOUR_BOT_TOKEN_HERE"
ADMIN_CHAT_ID = YOUR_ADMIN_CHAT_ID_HERE   # integer from @userinfobot

OLLAMA_URL    = "http://localhost:11434/api/generate"
OLLAMA_MODEL  = "llama3.2:3b"
INSTALLER     = str(Path(__file__).parent / "installer.sh")
LOG_FILE      = str(Path(__file__).parent / "deployments.log")

# How often to send an automatic progress update (seconds)
AUTO_UPDATE_INTERVAL = 120
# ═══════════════════════════════════════════════════════════════════

# ── Logging ──────────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("ChengetAi")

# ── Global state ─────────────────────────────────────────────────
is_busy: bool = False
deploy_queue: deque = deque()

# Tracks the active deployment so chat messages can reference it
active: dict | None = None
# Structure:
# {
#   "chat_id": int,
#   "domain":  str,
#   "ssl":     str,
#   "log":     list[str],   # rolling log buffer (last 150 lines)
#   "started": float,       # time.monotonic()
# }


# ═══════════════════════════════════════════════════════════════════
#  OLLAMA HELPERS  (both run in a thread — requests is synchronous)
# ═══════════════════════════════════════════════════════════════════

def _ollama_call(prompt: str, system: str, timeout: int = 90) -> str | None:
    """Blocking Ollama call — always run via asyncio.to_thread()."""
    payload = {
        "model":  OLLAMA_MODEL,
        "prompt": prompt,
        "system": system,
        "stream": False,
    }
    try:
        resp = requests.post(OLLAMA_URL, json=payload, timeout=timeout)
        resp.raise_for_status()
        raw = resp.json().get("response", "").strip()
        return raw
    except requests.exceptions.ConnectionError:
        log.error("Ollama not reachable (is it running?)")
        return None
    except Exception as exc:
        log.error(f"Ollama error: {exc}")
        return None


def _parse_deployment_params(user_message: str) -> dict | None:
    """Extract domain / ssl from a natural language request."""
    system = (
        "You are a deployment parser. Extract the domain and ssl (true/false) "
        "from the user's message. Return ONLY strict JSON, no markdown. "
        'Example: {"domain": "library.com", "ssl": true}. '
        "If no domain is mentioned use 'localhost'. Default ssl is false."
    )
    raw = _ollama_call(f"User: {user_message}", system)
    if not raw:
        return None
    raw = raw.replace("```json", "").replace("```", "").strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        log.error(f"JSON parse failed: {raw!r}")
        return None


def _chat_about_deployment(user_question: str, ctx: dict) -> str:
    """
    Conversational Ollama call while a deployment is running.
    ctx = active deployment dict.
    """
    elapsed_min = int((time.monotonic() - ctx["started"]) / 60)
    recent_logs = "\n".join(ctx["log"][-60:]) or "(no output yet)"

    system = (
        f"You are ChengetAi, a friendly AI deployment assistant. "
        f"You are currently deploying DSpace for '{ctx['domain']}' (SSL={ctx['ssl']}). "
        f"The installation has been running for {elapsed_min} minute(s).\n\n"
        f"Recent installer output:\n{recent_logs}\n\n"
        f"Answer the user's question conversationally. Be concise and friendly. "
        f"Use the logs to give accurate progress. "
        f"Typical DSpace install stages and durations:\n"
        f"  1. Docker setup:     ~1 min\n"
        f"  2. Pulling images:   ~5-8 min\n"
        f"  3. Database init:    ~1 min\n"
        f"  4. DSpace startup:   ~4-6 min\n"
        f"  5. Angular UI start: ~2 min\n"
        f"If you see errors in the logs, mention them clearly."
    )
    result = _ollama_call(user_question, system, timeout=60)
    return result or "I'm having trouble reaching the AI right now. The deployment is still running!"


def _generate_status_update(ctx: dict) -> str:
    """Auto-generate a friendly progress update from the current logs."""
    elapsed_min = int((time.monotonic() - ctx["started"]) / 60)
    recent_logs = "\n".join(ctx["log"][-40:]) or "(starting up...)"

    system = (
        f"You are ChengetAi. Summarise the current deployment progress for "
        f"'{ctx['domain']}' in 2-3 sentences. Be friendly and specific. "
        f"Elapsed time: {elapsed_min} min. Recent logs:\n{recent_logs}"
    )
    result = _ollama_call("Give a brief status update.", system, timeout=45)
    return result or f"Deployment running for {elapsed_min} min — still in progress..."


# ═══════════════════════════════════════════════════════════════════
#  DEPLOYMENT RUNNER
# ═══════════════════════════════════════════════════════════════════

async def run_deployment(chat_id: int, params: dict, app: Application) -> None:
    global is_busy, active

    domain = params.get("domain", "localhost")
    ssl    = "true" if params.get("ssl") else "false"
    admin_email = params.get("admin_email", f"admin@{domain}")
    admin_pass  = "ChengetAi2026!"

    active = {
        "chat_id": chat_id,
        "domain":  domain,
        "ssl":     ssl,
        "log":     [],
        "started": time.monotonic(),
    }

    env = {
        **os.environ,
        "DOMAIN":       domain,
        "ADMIN_EMAIL":  admin_email,
        "ADMIN_PASS":   admin_pass,
        "SSL_ENABLED":  ssl,
        "DEBIAN_FRONTEND": "noninteractive",
    }

    log.info(f"[{chat_id}] Starting: domain={domain} ssl={ssl}")

    await _safe_send(
        app, chat_id,
        f"🚀 *Deployment started!*\n\n"
        f"📌 Domain: `{domain}`\n"
        f"🔒 SSL:    `{ssl}`\n\n"
        f"⏱ This takes *5-10 minutes*. Feel free to chat with me while you wait!\n\n"
        f"💬 Try asking:\n"
        f"• _\"How's it going?\"_\n"
        f"• _\"What's happening now?\"_\n"
        f"• _\"How long is left?\"_",
        parse_mode="Markdown",
    )

    # Start auto-update task
    updater_task = asyncio.create_task(
        _auto_updater(chat_id, app)
    )

    try:
        process = await asyncio.create_subprocess_exec(
            "bash", INSTALLER,
            env=env,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )

        # Read stdout — feed into active["log"] for Ollama context
        while True:
            line_bytes = await process.stdout.readline()
            if not line_bytes:
                break
            line = line_bytes.decode("utf-8", errors="replace").rstrip()
            log.info(f"[{domain}] {line}")
            if active:
                active["log"].append(line)
                if len(active["log"]) > 150:   # keep rolling window
                    active["log"].pop(0)

        await process.wait()
        updater_task.cancel()

        elapsed = int(time.monotonic() - active["started"])

        if process.returncode == 0:
            proto = "https" if ssl == "true" else "http"
            await _safe_send(
                app, chat_id,
                f"✅ *Deployment complete!* ({elapsed}s)\n\n"
                f"🌐 `{proto}://{domain}/`\n"
                f"🔑 Login: `{proto}://{domain}/login`\n"
                f"📧 Email: `{admin_email}`\n"
                f"🔐 Pass:  `{admin_pass}`\n\n"
                f"_DSpace is live and ready to use._",
                parse_mode="Markdown",
            )
            log.info(f"[{chat_id}] Deployment of {domain} succeeded in {elapsed}s")
        else:
            await _safe_send(
                app, chat_id,
                f"❌ *Deployment failed* (exit {process.returncode}, {elapsed}s)\n\n"
                f"Ask me what went wrong and I'll check the logs for you.",
                parse_mode="Markdown",
            )

    except Exception as exc:
        updater_task.cancel()
        log.exception(f"[{chat_id}] Exception: {exc}")
        await _safe_send(
            app, chat_id,
            f"❌ *Unexpected error:*\n`{exc}`",
            parse_mode="Markdown",
        )
    finally:
        is_busy = False
        active  = None

        if deploy_queue:
            next_chat_id, next_params = deploy_queue.popleft()
            is_busy = True
            await _safe_send(
                app, next_chat_id,
                "⏳ Previous deployment finished. *Starting yours now...*",
                parse_mode="Markdown",
            )
            asyncio.create_task(run_deployment(next_chat_id, next_params, app))


async def _auto_updater(chat_id: int, app: Application) -> None:
    """Every AUTO_UPDATE_INTERVAL seconds, ask Ollama to summarise progress."""
    await asyncio.sleep(AUTO_UPDATE_INTERVAL)
    while is_busy and active:
        try:
            update_text = await asyncio.to_thread(_generate_status_update, active)
            await _safe_send(
                app, chat_id,
                f"📊 *Auto-update:*\n{update_text}",
                parse_mode="Markdown",
            )
        except Exception as exc:
            log.warning(f"Auto-updater error: {exc}")
        await asyncio.sleep(AUTO_UPDATE_INTERVAL)


async def _safe_send(app: Application, chat_id: int, text: str, **kwargs) -> None:
    try:
        await app.bot.send_message(chat_id, text, **kwargs)
        await asyncio.sleep(0.4)
    except Exception as exc:
        log.warning(f"Send failed to {chat_id}: {exc}")


# ═══════════════════════════════════════════════════════════════════
#  COMMAND HANDLERS
# ═══════════════════════════════════════════════════════════════════

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "👋 *Welcome to ChengetAi Deploy!*\n\n"
        "I deploy DSpace and chat with you while it installs.\n\n"
        "*Just tell me what you need:*\n"
        "• `Deploy DSpace for library.harare.ac.zw with SSL`\n"
        "• `Install on docs.hrepoly.ac.zw`\n"
        "• `Set up repository for research.uni.ac.zw`\n\n"
        "*While deploying, you can ask me anything:*\n"
        "• _\"How long is left?\"_\n"
        "• _\"What's happening now?\"_\n"
        "• _\"Is there an error?\"_\n\n"
        "/status — am I busy?\n"
        "/shutdown — stop the bot _(admin only)_",
        parse_mode="Markdown",
    )


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if is_busy and active:
        elapsed = int((time.monotonic() - active["started"]) / 60)
        q = len(deploy_queue)
        text = (
            f"⚙️ *Deploying* `{active['domain']}` ({elapsed} min elapsed)\n"
            f"Queue: {q} waiting."
        )
    else:
        text = "✅ *Idle* — ready to deploy!"
    await update.message.reply_text(text, parse_mode="Markdown")


async def cmd_shutdown(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_chat.id != ADMIN_CHAT_ID:
        await update.message.reply_text("❌ Admin-only command.")
        return
    await update.message.reply_text("🛑 Shutting down. Goodbye!")
    log.info("Shutdown by admin.")
    os._exit(0)


# ═══════════════════════════════════════════════════════════════════
#  MESSAGE HANDLER — routes to deploy OR conversation
# ═══════════════════════════════════════════════════════════════════

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    global is_busy

    chat_id   = update.effective_chat.id
    user_text = update.message.text.strip()
    log.info(f"[{chat_id}] Message: {user_text!r}")

    # ── Mode 1: Deployment is running AND this user started it ───
    # Route their message to Ollama for a conversational reply
    if is_busy and active and active["chat_id"] == chat_id:
        typing = await update.message.reply_text("🤔 Thinking...")
        try:
            reply = await asyncio.to_thread(_chat_about_deployment, user_text, active)
        except Exception as exc:
            reply = f"Sorry, couldn't reach the AI: {exc}"
        try:
            await typing.delete()
        except Exception:
            pass
        await update.message.reply_text(f"🤖 {reply}")
        return

    # ── Mode 2: Deployment running but different user OR idle user
    #    trying to queue/start a new deployment ───────────────────
    thinking = await update.message.reply_text("🤔 Analysing your request...")
    params = await asyncio.to_thread(_parse_deployment_params, user_text)

    try:
        await thinking.delete()
    except Exception:
        pass

    if not params:
        await update.message.reply_text(
            "❌ *Couldn't understand that.*\n\n"
            "Is Ollama running?\n`systemctl status ollama`\n\n"
            "Try: `Deploy DSpace for library.example.com with SSL`",
            parse_mode="Markdown",
        )
        return

    domain = params.get("domain", "localhost")
    ssl    = params.get("ssl", False)

    await update.message.reply_text(
        f"📋 *Parsed:*\nDomain: `{domain}`\nSSL: `{ssl}`",
        parse_mode="Markdown",
    )

    if is_busy:
        position = len(deploy_queue) + 1
        deploy_queue.append((chat_id, params))
        log.info(f"[{chat_id}] Queued at #{position}")
        await update.message.reply_text(
            f"⏳ *I'm busy with another deployment.*\n\n"
            f"You are *#{position}* in the queue.\n"
            f"I'll start yours automatically when finished.",
            parse_mode="Markdown",
        )
    else:
        is_busy = True
        asyncio.create_task(run_deployment(chat_id, params, context.application))


# ═══════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════

def main() -> None:
    if BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("ERROR: Set BOT_TOKEN in commander.py")
        sys.exit(1)
    if str(ADMIN_CHAT_ID) == "YOUR_ADMIN_CHAT_ID_HERE":
        print("ERROR: Set ADMIN_CHAT_ID in commander.py")
        sys.exit(1)

    log.info("=" * 55)
    log.info("ChengetAi Deploy — with live Ollama conversation")
    log.info(f"Model: {OLLAMA_MODEL}  |  Installer: {INSTALLER}")
    log.info("=" * 55)

    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start",    cmd_start))
    app.add_handler(CommandHandler("status",   cmd_status))
    app.add_handler(CommandHandler("shutdown", cmd_shutdown))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    log.info("Polling started. DM the bot /start to begin.")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
