# Harare Polytechnic Institutional Repository — DSpace 7.6 Installation

**Server:** `hrepolyREP` | **IP:** `192.168.26.3` (Static)

---

## Problem Identified from Server Photos

| Issue | Status | Fix |
|---|---|---|
| SSH not working (port 22) | Blocking | See Step 0 below |
| VMware ESXi wrong password | Blocking | Contact your VMware admin |
| Server accessible via Cockpit | ✓ | Use `https://192.168.26.3/` |

---

## Step 0 — Fix SSH Access (Do This First)

SSH is not connecting: `ssh root@192.168.26.3` → "Unknown error"

**Option A — Via Cockpit web terminal (recommended):**

1. Open browser → go to `https://192.168.26.3/`
2. Login with username `root` and your root password
3. Click **Terminal** in the left sidebar
4. Paste and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/main/scripts/00-fix-ssh.sh)
```

Or if you have this repo cloned on the server:

```bash
bash scripts/00-fix-ssh.sh
```

**Option B — Manually enable SSH:**

```bash
# On the server (via Cockpit terminal)
apt-get install -y openssh-server       # Ubuntu/Debian
systemctl enable --now ssh
ufw allow 22/tcp                        # If UFW firewall is active
```

After running, test SSH from your Windows machine:
```powershell
ssh root@192.168.26.3
```

---

## DSpace 7.6 Installation

### Architecture

```
Internet/LAN
     │
     ▼
  Nginx :80          ← Reverse proxy (port 80 to users)
  ├── /         →  DSpace Angular UI  (port 4000)
  ├── /server   →  DSpace REST API    (port 8080, Tomcat)
  └── /solr     →  Apache Solr        (port 8983, internal only)
                    PostgreSQL 15      (port 5432, internal only)
```

### Prerequisites

| Software | Version | Purpose |
|---|---|---|
| Ubuntu | 22.04+ | Operating System |
| Java (OpenJDK) | 17 | DSpace runtime |
| PostgreSQL | 15 | Database |
| Apache Tomcat | 10.1 | REST API servlet container |
| Apache Solr | 9.6 | Search engine |
| Node.js | 18 | Angular UI runtime |
| Nginx | latest | Reverse proxy |
| Maven | 3.9 | Build tool |

**Minimum hardware:** 2 CPU cores, 4GB RAM, 20GB free disk

---

## Quick Install (All-in-One)

After SSH access is working, run on the server as root:

```bash
# 1. Get the installation scripts
git clone https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git /opt/dspace-install
cd /opt/dspace-install

# 2. Make scripts executable
chmod +x scripts/*.sh

# 3. Run the master installer
bash scripts/install-all.sh
```

The installer will prompt for:
- Server hostname/IP (`192.168.26.3`)
- Database password
- Admin email, name, and password

**Installation takes approximately 20-40 minutes** (mostly Maven build time).

---

## Step-by-Step Install (Manual)

If you prefer to run each step individually:

```bash
# Step 0: Fix SSH (run via Cockpit terminal)
bash scripts/00-fix-ssh.sh

# Step 1: System pre-check
bash scripts/01-precheck.sh

# Step 2: Install Java, PostgreSQL, Tomcat, Solr, Node.js
bash scripts/02-install-dependencies.sh

# Step 3: Create DSpace database
bash scripts/03-configure-database.sh

# Step 4: Download, build and install DSpace backend
bash scripts/04-install-dspace.sh

# Step 5: Install DSpace Angular UI
bash scripts/05-install-angular-ui.sh

# Step 6: Create administrator account
bash scripts/06-create-admin.sh

# Step 7: Configure Nginx reverse proxy
bash scripts/07-configure-nginx.sh

# Step 8: Configure cron jobs for maintenance
bash scripts/08-scheduled-tasks.sh
```

---

## Post-Installation

### Verify Services Are Running

```bash
systemctl status tomcat       # DSpace REST API
systemctl status dspace-ui    # Angular frontend
systemctl status solr         # Search engine
systemctl status postgresql   # Database
systemctl status nginx        # Reverse proxy
```

### Access URLs

| URL | Service |
|---|---|
| `http://192.168.26.3/` | DSpace main UI |
| `http://192.168.26.3/login` | Admin login |
| `http://192.168.26.3/server/` | REST API |
| `http://192.168.26.3/server/api` | API browser |
| `http://192.168.26.3:8983/solr/` | Solr admin |

### Configuration Files

| File | Purpose |
|---|---|
| `/dspace/config/local.cfg` | Main DSpace config |
| `/opt/tomcat/conf/server.xml` | Tomcat config |
| `/etc/nginx/sites-available/dspace` | Nginx config |
| `/opt/dspace-ui/config/config.yml` | Angular UI config |

---

## Troubleshooting

### DSpace not starting
```bash
journalctl -u tomcat -n 50 --no-pager
cat /opt/tomcat/logs/catalina.out | tail -100
```

### Database connection error
```bash
# Test DB connection
PGPASSWORD=yourpassword psql -h localhost -U dspace -d dspace -c "SELECT 1;"

# Check PostgreSQL is running
systemctl status postgresql
```

### Solr not indexing
```bash
systemctl restart solr
# Reindex everything
/dspace/bin/dspace index-discovery -b
```

### UI blank page
```bash
systemctl restart dspace-ui
journalctl -u dspace-ui -n 50 --no-pager
```

### Reset admin password
```bash
/dspace/bin/dspace user --modify --email admin@example.com --newpassword newpassword
```

---

## Backup

Run manual backup:
```bash
dspace-backup
# Files saved to /var/backups/dspace/
```

Automated backups run nightly at 3am via cron (`/etc/cron.d/dspace`).

---

## VMware ESXi Access Issue

The ESXi console shows "incorrect username or password" for `admin`. To recover:

1. If you have physical access, use the DCUI (Direct Console UI) on the ESXi host
2. Boot from ESXi installation media in rescue mode
3. Or contact VMware support with your license key

The DSpace VM (`hrepolyREP`) is already running — ESXi access is needed only for VM management, not for DSpace itself.

---

## Support

- DSpace documentation: https://wiki.lyrasis.org/display/DSDOC7x/
- DSpace community: https://groups.google.com/g/dspace-tech
- DSpace GitHub: https://github.com/DSpace/DSpace
