# ChengetAI Deploy — Setup Guide

Deploy DSpace in plain English via Telegram. The bot uses a **local Ollama AI**
running on your Contabo VPS — no OpenAI account, no API fees.

---

## Architecture

```
You (Telegram) → Bot (commander.py) → Ollama (llama3.2:3b)
                                    ↓
                              installer.sh → Docker → DSpace live
```

---

## Step 1 — Install Ollama

SSH into your Contabo VPS, then:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Verify it is running:

```bash
systemctl status ollama
```

You should see `active (running)`. If not:

```bash
systemctl enable --now ollama
```

---

## Step 2 — Pull the AI model

```bash
ollama pull llama3.2:3b
```

This downloads a ~2 GB model that runs entirely on your server.
For better accuracy (needs more RAM):

```bash
ollama pull llama3:8b
```

Test it works:

```bash
ollama run llama3.2:3b "Say hello"
```

---

## Step 3 — Install Python dependencies

```bash
pip install python-telegram-bot requests
```

Or if you prefer a virtual environment:

```bash
python3 -m venv /opt/chengetai-venv
source /opt/chengetai-venv/bin/activate
pip install python-telegram-bot requests
```

---

## Step 4 — Create a Telegram bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot`
3. Give it a name, e.g. `ChengetAI Deploy`
4. Give it a username, e.g. `chengetai_deploy_bot`
5. BotFather replies with a token like:
   ```
   1234567890:ABCDefGhIJKlmNoPQRsTUVwxYz
   ```
   Copy this — it is your `BOT_TOKEN`.

---

## Step 5 — Get your Telegram user ID

1. Search for **@userinfobot** in Telegram
2. Send it any message
3. It replies with your user ID, e.g. `987654321`

This is your `ADMIN_CHAT_ID` — only this account can use `/shutdown`.

---

## Step 6 — Configure the bot

Copy the bot files to your server:

```bash
mkdir -p /opt/chengetai
scp bot/commander.py bot/installer.sh root@144.91.125.128:/opt/chengetai/
```

Or clone the repo directly on the server:

```bash
git clone -b claude/dspace-harare-polytechnic-install-0asotw \
  https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git \
  /opt/chengetai
cd /opt/chengetai/bot
```

Edit `commander.py` and replace the two placeholders:

```bash
nano /opt/chengetai/bot/commander.py
```

Find and replace:

```python
BOT_TOKEN     = "YOUR_BOT_TOKEN_HERE"        # ← paste your token
ADMIN_CHAT_ID = YOUR_ADMIN_CHAT_ID_HERE      # ← paste your user ID (no quotes)
```

Make the installer executable:

```bash
chmod +x /opt/chengetai/bot/installer.sh
```

---

## Step 7 — Run the bot

**Test run (stops when you close SSH):**

```bash
cd /opt/chengetai/bot
python3 commander.py
```

**Keep running after logout:**

```bash
nohup python3 /opt/chengetai/bot/commander.py > /opt/chengetai/bot/deployments.log 2>&1 &
echo "Bot PID: $!"
```

**Best option — run as a systemd service (auto-restarts on reboot):**

```bash
cat > /etc/systemd/system/chengetai.service << 'EOF'
[Unit]
Description=ChengetAI Deploy Bot
After=network.target ollama.service

[Service]
Type=simple
WorkingDirectory=/opt/chengetai/bot
ExecStart=/usr/bin/python3 /opt/chengetai/bot/commander.py
Restart=always
RestartSec=10
StandardOutput=append:/opt/chengetai/bot/deployments.log
StandardError=append:/opt/chengetai/bot/deployments.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now chengetai
systemctl status chengetai
```

---

## Step 8 — Test it

Open Telegram and send your bot:

```
Deploy DSpace for library.test.com with SSL
```

The bot will:
1. Reply "🤔 Analysing your request..."
2. Show parsed params: `domain: library.test.com, ssl: true`
3. Stream the installer output line by line
4. Finish with the URL, login email, and password

**Other test messages:**
```
Install DSpace on docs.hrepoly.ac.zw
Set up repository for research.uz.ac.zw with HTTPS
Deploy on 192.168.26.3
```

---

## Commands

| Command | Who | Description |
|---------|-----|-------------|
| `/start` | Anyone | Welcome message and usage |
| `/status` | Anyone | Is the bot busy? How long is the queue? |
| `/shutdown` | Admin only | Stop the bot cleanly |

---

## Logs

```bash
# Live log tail
tail -f /opt/chengetai/bot/deployments.log

# Container logs if deployment fails
docker logs dspace-backend
docker logs dspace-solr
docker compose -f /opt/dspace/docker-compose.yml ps
```

---

## Flags for manual use

The `installer.sh` can also be run manually:

```bash
# Basic install (uses server's public IP)
bash /opt/chengetai/bot/installer.sh

# Custom domain
DOMAIN=library.harare.ac.zw bash /opt/chengetai/bot/installer.sh

# With SSL (domain must have DNS pointing to this server)
DOMAIN=library.harare.ac.zw SSL_ENABLED=true bash /opt/chengetai/bot/installer.sh

# Full custom
DOMAIN=library.harare.ac.zw \
ADMIN_EMAIL=librarian@harare.ac.zw \
ADMIN_PASS=MySecurePass123 \
SSL_ENABLED=true \
bash /opt/chengetai/bot/installer.sh

# Update images, keep data
bash /opt/dspace/scripts/install.sh --update
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Bot doesn't respond | Check `systemctl status chengetai` |
| Ollama parse fails | Check `systemctl status ollama`, try `ollama run llama3.2:3b "test"` |
| SSL cert fails | Ensure DNS for domain points to this VPS IP before running |
| Port 80 busy | Run `fuser -k 80/tcp` then restart containers |
| Bad Gateway | Wait 2 min — Angular UI is still starting |
| DSpace 500 error | Run `docker logs dspace-backend` — usually a Solr core issue |
