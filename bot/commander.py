#!/usr/bin/env python3
"""
ChengetAI Deploy — Telegram Bot
Natural-language DSpace deployment using Ollama (local AI).

Usage:
    python3 commander.py

Requires:
    pip install python-telegram-bot requests
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
#  CONFIGURATION — edit these before running
# ═══════════════════════════════════════════════════════════════════
BOT_TOKEN     = "YOUR_BOT_TOKEN_HERE"
ADMIN_CHAT_ID = YOUR_ADMIN_CHAT_ID_HERE   # integer, get via @userinfobot

OLLAMA_URL    = "http://localhost:11434/api/generate"
OLLAMA_MODEL  = "llama3.2:3b"            # or "llama3:8b" for better accuracy

INSTALLER     = str(Path(__file__).parent / "installer.sh")
LOG_FILE      = str(Path(__file__).parent / "deployments.log")
# ═══════════════════════════════════════════════════════════════════

# ── Logging ─────────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("ChengetAI")

# ── Global state ─────────────────────────────────────────────────
is_busy: bool = False
deploy_queue: deque = deque()   # items: (chat_id: int, params: dict)


# ═══════════════════════════════════════════════════════════════════
#  OLLAMA — Natural language → deployment parameters
# ═══════════════════════════════════════════════════════════════════
SYSTEM_PROMPT = (
    "You are a deployment parser. Extract the domain, version, and ssl (true/false) "
    "from the user's message. Return ONLY strict JSON with no markdown and no extra text. "
    'Example: {"domain": "library.com", "version": "7.6", "ssl": true}. '
    "If no domain is mentioned, use 'localhost'. "
    "Default version is '7.6'. Default ssl is false."
)


def parse_with_ollama(user_message: str) -> dict | None:
    """Send user message to Ollama and return extracted params dict."""
    payload = {
        "model":  OLLAMA_MODEL,
        "prompt": f"User message: {user_message}",
        "system": SYSTEM_PROMPT,
        "stream": False,
    }
    try:
        log.info(f"Sending to Ollama: {user_message!r}")
        resp = requests.post(OLLAMA_URL, json=payload, timeout=90)
        resp.raise_for_status()
        raw = resp.json().get("response", "").strip()
        # Strip markdown code fences if model adds them
        raw = raw.replace("```json", "").replace("```", "").strip()
        log.info(f"Ollama raw response: {raw}")
        params = json.loads(raw)
        return params
    except requests.exceptions.ConnectionError:
        log.error("Ollama not reachable — is it running? (systemctl status ollama)")
        return None
    except (json.JSONDecodeError, KeyError, ValueError) as exc:
        log.error(f"Failed to parse Ollama response: {exc} | raw={raw!r}")
        return None
    except Exception as exc:
        log.error(f"Unexpected Ollama error: {exc}")
        return None


# ═══════════════════════════════════════════════════════════════════
#  DEPLOYMENT RUNNER
# ═══════════════════════════════════════════════════════════════════
async def run_deployment(chat_id: int, params: dict, app: Application) -> None:
    """
    Run installer.sh with the given params.
    Streams stdout line-by-line back to the Telegram user.
    When finished, processes the next item in the queue.
    """
    global is_busy

    domain      = params.get("domain", "localhost")
    ssl         = "true" if params.get("ssl") else "false"
    admin_email = params.get("admin_email", f"admin@{domain}")
    admin_pass  = params.get("admin_pass", "ChengetAI2026!")

    env = {
        **os.environ,
        "DOMAIN":       domain,
        "ADMIN_EMAIL":  admin_email,
        "ADMIN_PASS":   admin_pass,
        "SSL_ENABLED":  ssl,
        "DEBIAN_FRONTEND": "noninteractive",
    }

    log.info(f"[{chat_id}] Starting deployment: domain={domain} ssl={ssl}")
    start_time = time.monotonic()

    await _safe_send(
        app, chat_id,
        f"🚀 *Starting deployment*\n\n"
        f"📌 Domain: `{domain}`\n"
        f"🔒 SSL: `{ssl}`\n"
        f"📧 Admin: `{admin_email}`\n\n"
        f"_Streaming installer output below..._",
        parse_mode="Markdown",
    )

    try:
        process = await asyncio.create_subprocess_exec(
            "bash", INSTALLER,
            env=env,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )

        buffer: list[str] = []
        last_flush = asyncio.get_running_loop().time()

        async def flush() -> None:
            """Send buffered lines to Telegram, respecting message length limit."""
            nonlocal last_flush
            if not buffer:
                return
            chunk = "\n".join(buffer[-30:])   # last 30 lines max
            if len(chunk) > 3800:
                chunk = "..." + chunk[-3800:]  # Telegram 4096 char limit
            await _safe_send(app, chat_id, f"```\n{chunk}\n```", parse_mode="Markdown")
            buffer.clear()
            last_flush = asyncio.get_running_loop().time()

        # Read subprocess output line by line
        while True:
            line_bytes = await process.stdout.readline()
            if not line_bytes:
                break
            line = line_bytes.decode("utf-8", errors="replace").rstrip()
            log.info(f"[{chat_id}|{domain}] {line}")
            buffer.append(line)

            now = asyncio.get_running_loop().time()
            if len(buffer) >= 25 or (now - last_flush) >= 15:
                await flush()

        await flush()
        await process.wait()
        elapsed = int(time.monotonic() - start_time)

        if process.returncode == 0:
            proto = "https" if ssl == "true" else "http"
            await _safe_send(
                app, chat_id,
                f"✅ *Deployment complete!* ({elapsed}s)\n\n"
                f"🌐 URL:   `{proto}://{domain}/`\n"
                f"🔑 Login: `{proto}://{domain}/login`\n"
                f"📧 Email: `{admin_email}`\n"
                f"🔐 Pass:  `{admin_pass}`",
                parse_mode="Markdown",
            )
            log.info(f"[{chat_id}] Deployment of {domain} succeeded in {elapsed}s")
        else:
            await _safe_send(
                app, chat_id,
                f"❌ *Deployment failed* (exit {process.returncode}, {elapsed}s)\n\n"
                f"Check server logs:\n`docker logs dspace-backend`",
                parse_mode="Markdown",
            )
            log.error(f"[{chat_id}] Deployment of {domain} failed (exit {process.returncode})")

    except Exception as exc:
        log.exception(f"[{chat_id}] Deployment exception: {exc}")
        await _safe_send(
            app, chat_id,
            f"❌ *Unexpected error during deployment:*\n`{exc}`",
            parse_mode="Markdown",
        )
    finally:
        is_busy = False
        log.info(f"Queue size after finish: {len(deploy_queue)}")

        # Start next deployment in queue automatically
        if deploy_queue:
            next_chat_id, next_params = deploy_queue.popleft()
            is_busy = True
            log.info(f"Dequeuing deployment for chat {next_chat_id}")
            await _safe_send(
                app, next_chat_id,
                "⏳ The previous deployment finished. *Starting yours now...*",
                parse_mode="Markdown",
            )
            asyncio.create_task(run_deployment(next_chat_id, next_params, app))


async def _safe_send(app: Application, chat_id: int, text: str, **kwargs) -> None:
    """Send a Telegram message, silently ignoring send errors."""
    try:
        await app.bot.send_message(chat_id, text, **kwargs)
        await asyncio.sleep(0.5)   # basic rate-limit guard
    except Exception as exc:
        log.warning(f"Failed to send message to {chat_id}: {exc}")


# ═══════════════════════════════════════════════════════════════════
#  COMMAND HANDLERS
# ═══════════════════════════════════════════════════════════════════
async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "👋 *Welcome to ChengetAI Deploy!*\n\n"
        "I deploy DSpace institutional repositories using plain English.\n\n"
        "*Examples — just type:*\n"
        "• `Deploy DSpace for library.harare.ac.zw with SSL`\n"
        "• `Install on docs.hrepoly.ac.zw`\n"
        "• `Set up repository for research.uni.ac.zw with HTTPS`\n\n"
        "*Commands:*\n"
        "/status — am I busy?\n"
        "/shutdown — stop the bot _(admin only)_",
        parse_mode="Markdown",
    )


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if is_busy:
        q = len(deploy_queue)
        text = (
            f"⚙️ *Busy* — deployment in progress.\n"
            f"Queue: {q} waiting."
        )
    else:
        text = "✅ *Idle* — ready to deploy!"
    await update.message.reply_text(text, parse_mode="Markdown")


async def cmd_shutdown(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_chat.id != ADMIN_CHAT_ID:
        await update.message.reply_text("❌ Admin-only command.")
        return
    log.info("Shutdown requested by admin.")
    await update.message.reply_text("🛑 Shutting down ChengetAI Deploy. Goodbye!")
    os._exit(0)


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Parse the user's natural language request and queue or start deployment."""
    global is_busy

    chat_id   = update.effective_chat.id
    user_text = update.message.text.strip()
    log.info(f"[{chat_id}] Received: {user_text!r}")

    # ── Parse with Ollama ────────────────────────────────────────
    thinking_msg = await update.message.reply_text("🤔 Analysing your request with AI...")
    params = parse_with_ollama(user_text)

    # Delete the "thinking" message
    try:
        await thinking_msg.delete()
    except Exception:
        pass

    if not params:
        await update.message.reply_text(
            "❌ *I couldn't understand that.*\n\n"
            "Is Ollama running? (`systemctl status ollama`)\n\n"
            "Try phrasing like:\n"
            "`Deploy DSpace for library.example.com with SSL`",
            parse_mode="Markdown",
        )
        return

    domain = params.get("domain", "localhost")
    ssl    = params.get("ssl", False)

    await update.message.reply_text(
        f"📋 *Parsed request:*\n"
        f"Domain: `{domain}`\n"
        f"SSL:    `{ssl}`\n\n"
        f"{'Queuing...' if is_busy else 'Starting now...'}",
        parse_mode="Markdown",
    )

    # ── Queue or deploy ──────────────────────────────────────────
    if is_busy:
        position = len(deploy_queue) + 1
        deploy_queue.append((chat_id, params))
        log.info(f"[{chat_id}] Queued at position {position}")
        await update.message.reply_text(
            f"⏳ *I am currently busy with another deployment.*\n\n"
            f"You are *#{position}* in the queue.\n"
            f"I will start yours automatically when the current one finishes.",
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
        print("ERROR: Set BOT_TOKEN in commander.py before running.")
        sys.exit(1)
    if ADMIN_CHAT_ID == "YOUR_ADMIN_CHAT_ID_HERE":
        print("ERROR: Set ADMIN_CHAT_ID in commander.py before running.")
        sys.exit(1)

    log.info("=" * 50)
    log.info("ChengetAI Deploy starting")
    log.info(f"Installer: {INSTALLER}")
    log.info(f"Ollama model: {OLLAMA_MODEL}")
    log.info("=" * 50)

    app = (
        Application.builder()
        .token(BOT_TOKEN)
        .build()
    )

    app.add_handler(CommandHandler("start",    cmd_start))
    app.add_handler(CommandHandler("status",   cmd_status))
    app.add_handler(CommandHandler("shutdown", cmd_shutdown))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    log.info("Bot polling started. Send /start to your bot to test.")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
