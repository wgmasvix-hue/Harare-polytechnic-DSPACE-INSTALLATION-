# Harare Polytechnic Institutional Repository
## DSpace 7.6 — Complete Installation Package

**Target Host:** your server hostname or public IP | **OS:** Linux

---

## Quick Start

```bash
# On the server
git clone https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git /opt/dspace-install
cd /opt/dspace-install
cp .env.example .env && nano .env        # set passwords
make install                             # installs Docker + DSpace
make setup-collections                   # creates all HP faculties
make verify                              # confirms everything works
```

DSpace will be live at `http://YOUR_SERVER_HOST/`

To publish it on a public domain such as `unifiedrepo.dare.co.zw`, point DNS to the VPS IP, set `SERVER_HOST` in `.env` to that hostname, run `make ssl`, choose **Let's Encrypt**, and then rerun `docker compose up -d` plus `make verify HOST=unifiedrepo.dare.co.zw`.

---

## Problem: SSH Not Working

If your server responds over HTTP/HTTPS but SSH on port 22 is blocked, you can enable SSH from the web console.

**Fix via Cockpit web terminal:**

1. Open your server's web console in the browser
2. Log in as `root`
3. Click **Terminal** in the left sidebar
4. Paste:

```bash
apt-get install -y openssh-server && systemctl enable --now ssh && ufw allow 22
```

5. Test from another machine: `ssh root@YOUR_SERVER_HOST`

---

## Repository Structure

```
Harare Polytechnic Institutional Repository
│
├── Academic Departments
│   ├── Faculty of Engineering          (3 collections)
│   ├── Faculty of ICT & Electronics    (3 collections)
│   ├── Faculty of Business Management  (3 collections)
│   ├── Faculty of Applied Sciences     (2 collections)
│   ├── Faculty of Fashion & Textiles   (2 collections)
│   └── Faculty of Built Environment    (2 collections)
├── Research & Innovation Hub           (4 collections)
├── Library Collections                 (4 collections)
└── Student Works                       (2 collections)
```

---

## Installation Methods

### Method A — Docker (Recommended, Easiest)

Requires Docker. All dependencies run in containers.

```bash
make install           # ~10 minutes (downloads images)
make setup-collections # creates HP community structure
make verify            # health check
```

### Method B — Native Install (Manual)

Installs Java, PostgreSQL, Tomcat, Solr directly on the OS.

```bash
bash scripts/01-precheck.sh
bash scripts/02-install-dependencies.sh
bash scripts/03-configure-database.sh
bash scripts/04-install-dspace.sh       # ~30 min (Maven build)
bash scripts/05-install-angular-ui.sh
bash scripts/06-create-admin.sh
bash scripts/07-configure-nginx.sh
bash scripts/08-scheduled-tasks.sh
bash scripts/10-setup-collections.sh
```

---

## All Scripts

| Script | Purpose |
|---|---|
| `00-fix-ssh.sh` | Enable SSH on the server |
| `01-precheck.sh` | Check system requirements |
| `02-install-dependencies.sh` | Java 17, PostgreSQL 15, Tomcat 10, Solr 9 |
| `03-configure-database.sh` | Create DSpace database and user |
| `04-install-dspace.sh` | Build and install DSpace backend |
| `05-install-angular-ui.sh` | Install Angular frontend |
| `06-create-admin.sh` | Create admin account |
| `07-configure-nginx.sh` | Nginx reverse proxy |
| `08-scheduled-tasks.sh` | Cron jobs (indexing, backups) |
| `09-docker-install.sh` | All-in-one Docker installer |
| `10-setup-collections.sh` | Create HP faculty/collection structure |
| `11-verify-install.sh` | Post-install health check |
| `12-ssl-setup.sh` | HTTPS setup (self-signed or Let's Encrypt) |
| `13-monitoring.sh` | Install service health monitoring + alerts |

---

## Make Commands

```bash
make help              # show all commands
make install           # full Docker installation
make start             # start all services
make stop              # stop all services
make restart           # restart all services
make status            # show service status
make logs              # tail live logs
make verify            # health check
make backup            # manual database backup
make reindex           # rebuild Solr search index
make ssl               # setup HTTPS
```

---

## Service Architecture

```
Users (LAN / Internet)
        │
        ▼
   Nginx  :80/:443        ← entry point
   ├── /           →  Angular UI   (port 4000)
   ├── /server     →  REST API     (port 8080, Tomcat)
   └── internal:
       ├── Solr            (port 8983)
       └── PostgreSQL      (port 5432)
```

---

## Configuration

Copy `.env.example` to `.env` and set these values before installing:

```bash
SERVER_HOST=repo.example.edu   # server IP or hostname
DSPACE_DB_PASSWORD=...         # strong database password
DSPACE_ADMIN_EMAIL=...         # admin login email
DSPACE_ADMIN_PASS=...          # admin password
SMTP_HOST=mail.example.edu     # email server
```

Main DSpace config: `config/local.cfg`

If you are moving from an IP-based deployment to a public HTTPS hostname, update:

```bash
SERVER_HOST=unifiedrepo.dare.co.zw
PUBLIC_PROTOCOL=https
DSPACE_UI_SSL=true
DSPACE_REST_SSL=true
DSPACE_REST_PORT=443
```

Then run:

```bash
cd /opt/dspace-install
docker compose up -d
make verify HOST=unifiedrepo.dare.co.zw
```

---

## Post-Installation Checklist

- [ ] DSpace UI accessible at `http://YOUR_SERVER_HOST/`
- [ ] Admin login works at `http://YOUR_SERVER_HOST/login`
- [ ] All 6 faculty communities visible
- [ ] Test file upload — submit a sample document
- [ ] SSL/HTTPS configured (`make ssl`)
- [ ] Monitoring installed (`bash scripts/13-monitoring.sh`)
- [ ] Email alerts working (check `config/local.cfg` SMTP settings)
- [ ] Nightly backup cron active (`/etc/cron.d/dspace`)
- [ ] Register with OpenDOAR: https://www.openDOAR.org
- [ ] Register with Google Scholar: submit OAI-PMH URL

---

## System Requirements

| Item | Minimum | Recommended |
|---|---|---|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Disk | 20 GB | 100 GB |
| OS | Ubuntu 22.04 | Ubuntu 24.04 LTS |
| Java | OpenJDK 17 | OpenJDK 17 |
| PostgreSQL | 14 | 15 |

---

## Troubleshooting

**DSpace not starting:**
```bash
make logs
docker compose logs dspace
```

**Search not working:**
```bash
make reindex
```

**Database error:**
```bash
docker exec dspace-db psql -U dspace -d dspace -c "SELECT version();"
```

**Reset admin password:**
```bash
docker exec dspace-backend /dspace/bin/dspace user \
  --modify --email admin@example.edu --newpassword NewPass123!
```

**Full service restart:**
```bash
make restart
```

---

## Backup & Recovery

**Backup now:**
```bash
make backup
# Saved to /var/backups/dspace/
```

**Restore from backup:**
```bash
gunzip < /var/backups/dspace/dspace-YYYYMMDD.sql.gz | \
  docker exec -i dspace-db psql -U dspace dspace
```

Automated backups: nightly at 03:00 via `/etc/cron.d/dspace`

---

## Useful Links

| Resource | URL |
|---|---|
| DSpace 7.x Docs | https://wiki.lyrasis.org/display/DSDOC7x/ |
| DSpace Community | https://groups.google.com/g/dspace-tech |
| DSpace GitHub | https://github.com/DSpace/DSpace |
| OpenDOAR Registration | https://www.openDOAR.org |
| Handle.net Registration | https://www.handle.net |

---

## Support

- **IT Department:** Harare Polytechnic IT Services
- **Library:** set your institution's repository support email
- **DSpace Help:** https://groups.google.com/g/dspace-tech
