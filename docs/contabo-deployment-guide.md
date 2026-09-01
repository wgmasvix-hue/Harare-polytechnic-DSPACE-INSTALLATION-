# Contabo VPS Deployment Guide
## Bulawayo Polytechnic Repository — DSpace 9.3

**VM Specs:** Ubuntu 22.04 LTS | 8 GB RAM | Contabo VPS M  
**Access:** SSH via public IP

---

## Step 1 — Get Your Contabo IP

Log into Contabo Customer Panel → your VPS IP is shown on the dashboard: `157.173.127.168`.

Create an `A` record for `BulawayoPolytechnicRepository.dare.co.zw` that points to this IP before installation.

---

## Step 2 — SSH Into Your VM

From Windows PowerShell:
```powershell
ssh root@YOUR_CONTABO_IP
```

Contabo sends the root password to your email when you order the VPS.

---

## Step 3 — Harden the Server (Optional but Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/15-harden-server.sh | bash
```

This sets up:
- Firewall (UFW) — ports 22, 80, 443 only
- Fail2ban — blocks brute-force SSH attacks
- 4GB swap file
- Automatic security updates

---

## Step 4 — One-Command DSpace Install

```bash
curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/install.sh | sudo bash
```

The installer configures Caddy with automatic HTTPS for `BulawayoPolytechnicRepository.dare.co.zw` and generates strong database and administrator passwords. Save the printed administrator credentials securely. To supply your own values, prefix the command with `SERVER_HOST`, `DSPACE_ADMIN_EMAIL`, `DSPACE_ADMIN_PASS`, and `DSPACE_DB_PASSWORD`.

Installation takes **10–20 minutes** (mostly pulling Docker images).

---

## Step 5 — Create HP Faculty Structure

```bash
cd /opt/dspace-install
make setup-collections
```

Creates all faculties, departments, and collections automatically.

---

## Step 6 — Verify Everything Works

```bash
make verify YOUR_CONTABO_IP
```

---

## Step 7 — Enable HTTPS (When You Get a Domain)

If you point a domain like `repo.hrepoly.ac.zw` to your Contabo IP:

```bash
make ssl
# Choose option 2 (Let's Encrypt)
# Enter: repo.hrepoly.ac.zw
```

Free SSL certificate, auto-renews every 90 days.

Without a domain, run `make ssl` and choose option 1 (self-signed).

---

## Useful Commands on the VM

```bash
cd /opt/dspace-install

make status       # see all containers running
make logs         # live logs
make restart      # restart everything
make backup       # backup database now
make reindex      # rebuild search index
```

---

## Firewall Ports Open on Contabo

| Port | Service | Access |
|---|---|---|
| 22 | SSH | Your IP only (after hardening) |
| 80 | HTTP → DSpace UI | Public |
| 443 | HTTPS → DSpace UI | Public |
| 8080 | Tomcat (REST API) | Internal only |
| 8983 | Solr | Internal only |
| 5432 | PostgreSQL | Internal only |

---

## Access URLs (replace with your IP)

| URL | What it is |
|---|---|
| `http://YOUR_IP/` | DSpace homepage |
| `http://YOUR_IP/login` | Admin login |
| `http://YOUR_IP/server/` | REST API |
| `http://YOUR_IP/server/api` | API browser |

---

## Troubleshooting Contabo-Specific Issues

**Port 80 not accessible from outside:**
```bash
ufw status          # should show 80 ALLOW
ufw allow 80/tcp
```

**Docker not starting after reboot:**
```bash
systemctl enable docker
cd /opt/dspace-install && docker compose up -d
```

**Add auto-start on reboot:**
```bash
crontab -e
# Add this line:
@reboot cd /opt/dspace-install && docker compose up -d
```

**Out of disk space:**
```bash
df -h                          # check usage
docker system prune -f         # remove unused images
```

**Check DSpace logs:**
```bash
docker compose logs -f dspace-backend    # backend errors
docker compose logs -f dspace-frontend   # UI errors
```
