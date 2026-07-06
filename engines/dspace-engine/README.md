# ChengetAi DSpace Engine

[![Engine](https://img.shields.io/badge/ChengetAi-DSpace%20Engine-blue)](https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-)
[![DSpace](https://img.shields.io/badge/DSpace-8.x-orange)](https://dspace.lyrasis.org/)

One-command deployment of a production-ready **DSpace 8.x** Institutional Repository using Docker.

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git
cd harare-polytechnic-dspace-installation-/engines/dspace-engine

# 2. Configure
cp .env.example .env
nano .env          # set DSPACE_HOSTNAME, POSTGRES_PASSWORD, ADMIN_EMAIL, ADMIN_PASSWORD

# 3. Deploy
sudo bash scripts/install.sh
```

DSpace will be live at the URL you set in `.env`.

---

## ChengetAi CLI Commands

| Command | Description |
|---|---|
| `chengetai deploy dspace` | Full installation |
| `chengetai backup dspace` | Backup database + assetstore |
| `chengetai restore dspace` | Restore from backup |
| `chengetai update dspace` | Pull new images + rolling restart |
| `chengetai uninstall dspace` | Remove containers (data kept) |
| `chengetai status dspace` | Health check all services |

---

## Architecture

```
Users (HTTP/HTTPS)
       │
       ▼
  Nginx  :80 / :443           ← entry point
  ├── /              → Angular UI      (dspace-frontend:4000)
  └── /server        → REST API        (dspace-backend:8080)
                              │
                    ┌─────────┴──────────┐
                    ▼                    ▼
              PostgreSQL 15          Solr (dspace-8_x)
            (dspace-pgdata)        (dspace-solrdata)
```

---

## Directory Structure

```
engines/
├── common/                  Shared library — sourced by all engines
│   ├── logging.sh           Coloured logging, log-file write
│   ├── docker.sh            Docker / Compose helpers
│   ├── backup.sh            Database + volume backup helpers
│   ├── ssl.sh               Self-signed + Let's Encrypt helpers
│   └── healthcheck.sh       HTTP, container, disk checks
│
└── dspace-engine/
    ├── docker/
    │   └── postgres-init.sql   DB initialization (pgcrypto)
    ├── config/
    │   ├── nginx.conf           Nginx config (rewritten by ssl-setup.sh)
    │   └── local.cfg            Rendered DSpace config (generated)
    ├── templates/
    │   └── local.cfg.tpl        DSpace config template
    ├── scripts/
    │   ├── install.sh           Main installer (idempotent)
    │   ├── create-site.sh       Create community/collection structure
    │   ├── create-admin.sh      Create / reset admin account
    │   ├── backup.sh            Backup database + assetstore
    │   ├── restore.sh           Restore from backup
    │   ├── update.sh            Pull new images + rolling restart
    │   ├── uninstall.sh         Remove containers (--purge for data too)
    │   ├── healthcheck.sh       Health check all services
    │   └── ssl-setup.sh         Enable HTTPS (self-signed or Let's Encrypt)
    ├── docs/
    │   └── deployment-guide.md  Detailed deployment guide
    ├── docker-compose.yml
    ├── engine.yml               ChengetAi engine manifest
    ├── .env.example
    └── README.md
```

---

## Configuration

Copy `.env.example` to `.env` and set the following before running `install.sh`:

| Variable | Required | Description |
|---|---|---|
| `DSPACE_HOSTNAME` | ✅ | Domain or IP of the server |
| `POSTGRES_PASSWORD` | ✅ | Strong database password |
| `ADMIN_EMAIL` | ✅ | DSpace admin email |
| `ADMIN_PASSWORD` | ✅ | DSpace admin password |
| `DSPACE_NAME` | — | Repository display name |
| `PUBLIC_PROTOCOL` | — | `http` or `https` (default: `http`) |
| `SMTP_HOST` | — | SMTP server hostname |
| `SMTP_PORT` | — | SMTP port (default: 25) |
| `MAIL_FROM` | — | Sender email address |
| `HANDLE_PREFIX` | — | Handle.net prefix (default: `123456789`) |
| `JAVA_MEMORY` | — | JVM heap (default: `-Xmx2g -Xms512m`) |
| `SOLR_MEMORY` | — | Solr heap (default: `512m`) |
| `BACKUP_ROOT` | — | Backup destination directory |
| `BACKUP_RETENTION_DAYS` | — | Days to keep backups (default: 30) |

---

## SSL / HTTPS

### Let's Encrypt (recommended for public servers)

```bash
sudo bash scripts/ssl-setup.sh --letsencrypt
```

Requires a public domain and ports 80/443 open. Auto-renewal is configured automatically.

### Self-signed (for LAN / intranet)

```bash
sudo bash scripts/ssl-setup.sh --selfsigned
```

Browsers will show a warning. Import the certificate into your trust store to suppress it.

---

## Backup & Restore

```bash
# Backup
sudo bash scripts/backup.sh
# Backups saved to /var/backups/chengetai/dspace/<timestamp>/

# Restore
sudo bash scripts/restore.sh /var/backups/chengetai/dspace/20250101_120000
```

Automated nightly backups can be configured with:

```bash
echo "0 3 * * * root bash /opt/dspace-install/engines/dspace-engine/scripts/backup.sh" \
  >> /etc/cron.d/chengetai-dspace
```

---

## Updating DSpace

```bash
# Pull latest images within the same major version
sudo bash scripts/update.sh

# Major version upgrade
sudo bash scripts/update.sh --major
```

---

## System Requirements

| Item | Minimum | Recommended |
|---|---|---|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Disk | 20 GB | 100 GB |
| OS | Ubuntu 22.04 | Ubuntu 24.04 LTS |
| Docker | 24.0+ | latest |
| Docker Compose | 2.20+ | latest |

---

## Troubleshooting

**Services not starting:**
```bash
docker compose -f engines/dspace-engine/docker-compose.yml logs -f
```

**Backend stuck initializing:**
```bash
docker logs dspace-backend --tail=50
```

**Search not working:**
```bash
docker exec dspace-backend /dspace/bin/dspace index-discovery -b
```

**Reset admin password:**
```bash
bash engines/dspace-engine/scripts/create-admin.sh
```

---

## Contributing

This engine is part of the ChengetAi Deploy plugin system.
Each engine contains only application-specific logic; all shared infrastructure
(Docker management, backups, SSL, logging, health checks) lives in `engines/common/`.

---

## License

MIT — see repository root for details.
