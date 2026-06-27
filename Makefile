# =================================================================
#  Harare Polytechnic DSpace 7.6 — Makefile
#  Usage:  make <target>
#  Run on your target host as root
# =================================================================

.PHONY: help install start stop restart status logs backup verify \
        fix-ssh check setup-collections ssl clean

SHELL := /bin/bash
HOST  ?= localhost

help:
	@echo ""
	@echo "  Harare Polytechnic DSpace — Command Reference"
	@echo ""
	@echo "  INSTALLATION"
	@echo "    make fix-ssh          Fix SSH access (run via Cockpit terminal)"
	@echo "    make check            Pre-installation system check"
	@echo "    make install          Full Docker-based installation"
	@echo "    make setup-collections  Create HP faculty/collection structure"
	@echo ""
	@echo "  DAY-TO-DAY"
	@echo "    make start            Start all DSpace services"
	@echo "    make stop             Stop all DSpace services"
	@echo "    make restart          Restart all services"
	@echo "    make status           Show service status"
	@echo "    make logs             Tail live logs"
	@echo "    make verify           Verify everything is working"
	@echo ""
	@echo "  MAINTENANCE"
	@echo "    make backup           Run manual backup"
	@echo "    make reindex          Rebuild Solr search index"
	@echo "    make ssl              Setup HTTPS (self-signed cert)"
	@echo "    make clean            Remove containers and volumes (CAUTION)"
	@echo ""

fix-ssh:
	@bash scripts/00-fix-ssh.sh

check:
	@bash scripts/01-precheck.sh

install:
	@bash scripts/09-docker-install.sh

setup-collections:
	@bash scripts/10-setup-collections.sh

verify:
	@bash scripts/11-verify-install.sh $(HOST)

ssl:
	@bash scripts/12-ssl-setup.sh

start:
	@echo "Starting DSpace services..."
	@docker compose up -d 2>/dev/null || \
	 (systemctl start postgresql solr tomcat dspace-ui nginx && echo "Services started")
	@echo "DSpace is at http://$(HOST)/"

stop:
	@echo "Stopping DSpace services..."
	@docker compose down 2>/dev/null || \
	 systemctl stop dspace-ui tomcat solr

restart:
	@echo "Restarting DSpace services..."
	@docker compose restart 2>/dev/null || \
	 (systemctl restart tomcat dspace-ui solr nginx && echo "Restarted")

status:
	@echo "=== DSpace Service Status ==="
	@docker compose ps 2>/dev/null || \
	 (systemctl status postgresql solr tomcat dspace-ui nginx --no-pager -l)

logs:
	@docker compose logs -f --tail=50 2>/dev/null || \
	 journalctl -f -u tomcat -u dspace-ui

backup:
	@echo "Running DSpace backup..."
	@bash -c 'PGPASSWORD=$${DSPACE_DB_PASSWORD:-change-this-database-password} \
	  pg_dump -h localhost -U dspace dspace | gzip > /var/backups/dspace/dspace-$$(date +%Y%m%d_%H%M%S).sql.gz && \
	  echo "Backup saved to /var/backups/dspace/"' 2>/dev/null || \
	 docker exec dspace-db bash -c \
	   'pg_dump -U dspace dspace | gzip > /tmp/dspace-backup.sql.gz && echo "Backup done"'

reindex:
	@echo "Rebuilding Solr search index..."
	@docker exec dspace-backend /dspace/bin/dspace index-discovery -b 2>/dev/null || \
	 sudo -u dspace /dspace/bin/dspace index-discovery -b
	@echo "Reindex complete"

clean:
	@echo "WARNING: This removes all containers and data volumes!"
	@read -p "Type YES to confirm: " C && [ "$$C" = "YES" ] && \
	 docker compose down -v || echo "Aborted."
