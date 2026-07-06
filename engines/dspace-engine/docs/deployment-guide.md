# ChengetAi DSpace Engine — Deployment Guide

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Contabo / Cloud VPS Setup](#2-contabo--cloud-vps-setup)
3. [Step-by-step Installation](#3-step-by-step-installation)
4. [SSL Configuration](#4-ssl-configuration)
5. [Creating Repository Structure](#5-creating-repository-structure)
6. [Automated Backups](#6-automated-backups)
7. [Monitoring](#7-monitoring)
8. [Upgrading DSpace](#8-upgrading-dspace)
9. [OAI-PMH & Discovery Registration](#9-oai-pmh--discovery-registration)

---

## 1. Prerequisites

- Ubuntu 22.04 or 24.04 LTS (recommended)
- At least 4 GB RAM, 20 GB disk, 2 CPU cores
- Root or sudo access
- Internet connectivity (to pull Docker images)
- A domain name pointing to the server (for Let's Encrypt SSL)

---

## 2. Contabo / Cloud VPS Setup

```bash
# 1. Update the system
apt update && apt upgrade -y

# 2. Open only required ports
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

# 3. Add swap (important for low-RAM VMs)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 4. Create DNS A record:
#    repo.yourdomain.com → <your server IP>
```

---

## 3. Step-by-step Installation

```bash
# Clone the engine repository
git clone https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git \
  /opt/dspace-install
cd /opt/dspace-install/engines/dspace-engine

# Configure
cp .env.example .env
nano .env
# Required settings:
#   DSPACE_HOSTNAME=repo.yourdomain.com
#   POSTGRES_PASSWORD=<strong-password>
#   ADMIN_EMAIL=admin@yourdomain.com
#   ADMIN_PASSWORD=<strong-password>
#   DSPACE_NAME=My University Repository

# Deploy (~10-15 minutes for image pulls on first run)
sudo bash scripts/install.sh
```

The installer is **idempotent** — safe to run again if interrupted.

---

## 4. SSL Configuration

### Let's Encrypt (public servers with a domain)

```bash
sudo bash scripts/ssl-setup.sh --letsencrypt
```

This:
- Installs Certbot
- Obtains a free trusted certificate
- Updates `nginx.conf` to redirect HTTP → HTTPS
- Updates `local.cfg` with `https://` URLs
- Configures auto-renewal

### Self-signed (LAN / intranet)

```bash
sudo bash scripts/ssl-setup.sh --selfsigned
```

---

## 5. Creating Repository Structure

After install, create a default community/collection hierarchy:

```bash
bash scripts/create-site.sh
```

You can edit `scripts/create-site.sh` to match your institution's structure before running it.

---

## 6. Automated Backups

Add to root crontab for nightly backups at 03:00:

```bash
echo "0 3 * * * root bash /opt/dspace-install/engines/dspace-engine/scripts/backup.sh >> /var/log/chengetai/backup.log 2>&1" \
  >> /etc/cron.d/chengetai-dspace
```

Backups are saved to `/var/backups/chengetai/dspace/<timestamp>/` and contain:

| File | Contents |
|---|---|
| `dspace-<timestamp>.sql.gz` | PostgreSQL dump |
| `assetstore-<timestamp>.tar.gz` | All uploaded files |
| `dspace-config-<timestamp>.tar.gz` | DSpace config volume |
| `env.snapshot` | `.env` at time of backup |
| `MANIFEST.txt` | Backup metadata |

Old backups are pruned automatically after `BACKUP_RETENTION_DAYS` (default: 30).

---

## 7. Monitoring

Run a manual health check:

```bash
bash scripts/healthcheck.sh
# or
chengetai status dspace
```

For continuous monitoring, add to crontab:

```bash
echo "*/5 * * * * root bash /opt/dspace-install/engines/dspace-engine/scripts/healthcheck.sh >> /var/log/chengetai/health.log 2>&1" \
  >> /etc/cron.d/chengetai-dspace
```

---

## 8. Upgrading DSpace

### Minor / patch update (within same major version)

```bash
sudo bash scripts/update.sh
```

This creates a backup, pulls new images, performs a rolling restart, and re-runs migrations.

### Major version upgrade

```bash
sudo bash scripts/update.sh --major
# Follow prompts to update DSPACE_*_TAG values in .env
```

---

## 9. OAI-PMH & Discovery Registration

Once live at `https://repo.yourdomain.com`, register your repository:

| Registry | URL | Submit |
|---|---|---|
| **OpenDOAR** | https://www.openDOAR.org | Register your repository |
| **ROAR** | https://roar.eprints.org | Register your repository |
| **Google Scholar** | — | Submit OAI-PMH URL |
| **BASE** | https://www.base-search.net | Register your OAI-PMH endpoint |

Your OAI-PMH URL is:

```
https://repo.yourdomain.com/server/oai/request?verb=Identify
```

---

## Useful Docker Commands

```bash
# Service status
docker compose -f engines/dspace-engine/docker-compose.yml ps

# Live logs
docker compose -f engines/dspace-engine/docker-compose.yml logs -f

# Restart a single service
docker compose -f engines/dspace-engine/docker-compose.yml restart dspace

# Execute command in backend
docker exec -it dspace-backend /dspace/bin/dspace help
```
