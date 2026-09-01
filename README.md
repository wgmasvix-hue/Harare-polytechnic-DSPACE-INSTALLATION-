# Harare Polytechnic Institutional Repository
## DSpace 9 — Complete Installation Package

**Server:** `hrepolyREP` | **IP:** `192.168.26.3` (Static LAN) | **OS:** Linux

---

## Quick Start

Clone and install in one command:

```bash
git clone https://github.com/wgmasvix-hue/Harare-polytechnic-DSPACE-INSTALLATION-.git /opt/dspace-install && \
  cd /opt/dspace-install && \
  cp .env.example .env && \
  nano .env && \
  make install && \
  make setup-collections && \
  make verify
```

DSpace will be live at `http://192.168.26.3/`

---

## Problem: SSH Not Working

Your server is visible on the network (`https://192.168.26.3/` responds) but SSH on port 22 is blocked.

**Fix via Cockpit web terminal:**

1. Open `https://192.168.26.3/` in your browser
2. Log in as `root`
3. Click **Terminal** in the left sidebar
4. Paste:

```bash
apt-get install -y openssh-server && systemctl enable --now ssh && ufw allow 22
```

5. Test from Windows: `ssh root@192.168.26.3`

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
SERVER_HOST=192.168.26.3       # server IP or hostname
DSPACE_DB_PASSWORD=...         # strong database password
DSPACE_ADMIN_EMAIL=...         # admin login email
DSPACE_ADMIN_PASS=...          # admin password
SMTP_HOST=mail.hrepoly.ac.zw   # email server
```

Main DSpace config: `config/local.cfg`

---

## Post-Installation Checklist

- [ ] DSpace UI accessible at `http://192.168.26.3/`
- [ ] Admin login works at `http://192.168.26.3/login`
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
  --modify --email admin@hrepoly.ac.zw --newpassword NewPass123!
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
- **Library:** library@hrepoly.ac.zw
- **DSpace Help:** https://groups.google.com/g/dspace-tech
