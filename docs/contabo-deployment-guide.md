# Contabo VPS Deployment Guide
## Harare Polytechnic DSpace 7.6

**VM Specs:** Ubuntu 22.04 LTS | 8 GB RAM | Contabo VPS M  
**Access:** SSH via public IP

---

## Step 1 — Get Your Contabo IP

Log into Contabo Customer Panel → your VPS IP is shown on the dashboard.  
Example: `85.215.xxx.xxx`

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
curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/14-contabo-deploy.sh | bash
```

You will be prompted for:
- Your Contabo public IP (auto-detected)
- Your public hostname/domain (for example `unifiedrepo.dare.co.zw`; leave the default IP if DNS is not ready yet)
- Database password
- Admin email and password

Installation takes **10–20 minutes** (mostly pulling Docker images).

---

## Step 5 — Point DNS to the VPS

Create an **A record** for your public hostname and point it to the Contabo VPS public IP.

Example:

```text
Type:   A
Name:   unifiedrepo.dare.co.zw
Value:  YOUR_CONTABO_PUBLIC_IP
TTL:    300
```

Wait for DNS to resolve publicly before requesting a Let's Encrypt certificate.

---

## Step 6 — Create HP Faculty Structure

```bash
cd /opt/dspace-install
make setup-collections
```

Creates all faculties, departments, and collections automatically.

---

## Step 7 — Enable HTTPS for the Public Domain

If your repository should be public on `unifiedrepo.dare.co.zw`, update `/opt/dspace-install/.env` so it uses the hostname instead of the IP:

```bash
cd /opt/dspace-install
nano .env
```

Set:

```bash
SERVER_HOST=unifiedrepo.dare.co.zw
PUBLIC_PROTOCOL=https
DSPACE_UI_SSL=true
DSPACE_REST_SSL=true
DSPACE_REST_PORT=443
```

Then request the certificate:

```bash
cd /opt/dspace-install
make ssl
# Choose option 2 (Let's Encrypt)
# Enter: unifiedrepo.dare.co.zw
docker compose up -d
```

The SSL script updates the stack for HTTPS and rewrites the public URLs to the selected hostname.

---

## Step 8 — Verify Everything Works

```bash
cd /opt/dspace-install
make verify HOST=unifiedrepo.dare.co.zw
```

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

## Public Endpoints

| URL | What it is |
|---|---|
| `https://unifiedrepo.dare.co.zw/` | DSpace homepage |
| `https://unifiedrepo.dare.co.zw/login` | Admin login |
| `https://unifiedrepo.dare.co.zw/server/api` | REST API browser |

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
docker compose logs -f dspace-nginx      # nginx errors
```
