# LibreTime Migration Guide - Jupiter to Venus
## Using RadioStack with Automatic Volume Fix

**Last Updated:** December 31, 2024
**RadioStack Branch:** fix/VolumeFix
**Tested On:** aconcagua2 (CT152) - Production ✅

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 🎯 Overview

This guide covers migrating LibreTime stations from Jupiter (old server) to Venus (Proxmox) using RadioStack's automatic deployment with the volume fix.

**Stations to Migrate:**
- ✅ aconcagua2 (CT152) - DONE
- ⏳ djsclub (CT154) - NEXT
- ⏳ aconcagua3 (CT153)
- ⏳ djsclub2 (CT154)
- ⏳ djsclub (CT154)

**Time per Station:** ~2.5 hours (down from 3 hours with manual fix)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 📋 Prerequisites (One-Time Setup)

### On Venus (Proxmox Host)

```bash
# Ensure you're on the fix branch
cd /mnt/datos1/00-TecnoSoul/00-Servers/RadioStack
git fetch origin
git checkout fix/VolumeFix
git pull origin fix/VolumeFix

# Verify you have the latest code with volume fix
git log --oneline -3
# Should show:
# eab9dce chore: Clean up repository structure
# decef11 feat: Add automatic LibreTime volume mount fix
# 8888fbb docs: Clean up documentation for v1.0.0 release
```

### On Jupiter (Old Server)

```bash
# Prepare backup directory
mkdir -p /root/libretime-backups
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 📝 Migration Scenarios

This guide covers two Jupiter source configurations:

**Scenario A: Jupiter with Docker LibreTime**
- Database: Use `docker compose exec postgres pg_dump`
- Media: `/var/lib/docker/volumes/libretime_storage/_data/`
- Config: `config.yml`, `.env`, `docker-compose.yml`

**Scenario B: Jupiter with Bare Metal LibreTime**
- Database: Use `sudo -u postgres pg_dump -F c`
- Media: `/srv/libretime/` (or custom path)
- Config: N/A (manual configuration)

**Command Execution Methods:**
- **Method 1 (Recommended)**: From Venus host using `pct exec <CTID> -- <command>`
- **Method 2**: Inside container using `pct enter <CTID>` then run commands directly

Both methods are shown throughout this guide.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 🚀 Migration Steps (Per Station)

### STEP 1: Backup on Jupiter (~10 minutes)

```bash
# SSH to Jupiter
ssh root@jupiter

# Set variables (adjust for each station)
STATION_NAME="aconcagua1"
BACKUP_DATE=$(date +%Y%m%d)

# 1. Backup database
# Option A: If Jupiter uses Docker LibreTime
cd /opt/libretime
docker compose exec -T postgres pg_dump -U libretime libretime \
  > /root/libretime-backups/${STATION_NAME}-db-${BACKUP_DATE}.sql

# Option B: If Jupiter uses bare metal PostgreSQL (custom format for faster restore)
sudo -u postgres pg_dump -F c libretime > /tmp/${STATION_NAME}-backup.dump

# 2. Backup configuration (only if Docker setup)
tar czf /root/libretime-backups/${STATION_NAME}-config-${BACKUP_DATE}.tar.gz \
  config.yml .env docker-compose.yml

# 3. Get database size (for reference)
ls -lh /root/libretime-backups/${STATION_NAME}-db-${BACKUP_DATE}.sql
# OR for custom format:
ls -lh /tmp/${STATION_NAME}-backup.dump

# 4. Note media location
# Docker setup:
df -h /var/lib/docker/volumes/libretime_storage/_data
# Bare metal setup:
df -h /srv/libretime
```

### STEP 2: Deploy on Venus (~5 minutes)

```bash
# SSH to Venus
ssh root@venus

# Navigate to RadioStack
cd /mnt/datos1/00-TecnoSoul/00-Servers/RadioStack

# Deploy LibreTime (with automatic volume fix!)
sudo ./scripts/platforms/libretime.sh \
  -i 154 \
  -n djsclub \
  -c 4 \
  -m 8192 \
  -q 100G \
  -p 154

# Wait 3-5 minutes for deployment to complete
# You'll see: "✓ Volume mounts configured for HDD storage"
```

### STEP 3: Verify Volume Fix (~2 minutes)

```bash
# 1. Check docker-compose.yml has host mounts
pct exec 154 -- grep "/srv/libretime:/srv/libretime" /opt/libretime/docker-compose.yml
# ✅ Should show multiple matches

# 2. Verify storage is on HDD pool
pct exec 154 -- df -h /srv/libretime
# ✅ Should show: hdd-pool/container-data/libretime-media/djsclub

# 3. Confirm Docker volume doesn't exist
pct exec 154 -- docker volume ls | grep libretime_storage
# ✅ Should return nothing

# 4. Check all services are running
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml ps
# ✅ All services should show "Up"
```

### STEP 4: Transfer Database (~5 minutes)

```bash
# Transfer database backup from Jupiter to Venus
# Option A: If Jupiter uses Docker (standard setup)
scp root@jupiter:/root/libretime-backups/aconcagua1-db-*.sql /tmp/

# Option B: If Jupiter uses bare metal PostgreSQL (custom setup)
# From Jupiter, create backup:
#   sudo -u postgres pg_dump -F c libretime > /tmp/libretime-backup.dump
# Then rsync to Venus:
rsync -avzP --info=progress2 -e 'ssh -p 22' \
  root@jupiter:/tmp/libretime-backup.dump \
  /hdd-pool/migration-jupiter/aconcagua1/

# Push backup file to container
pct push 151 /hdd-pool/migration-jupiter/aconcagua1/libretime-backup.dump /tmp/libretime-db.dump

# Stop services before database restore
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml stop

# Restore database
# Method 1: From Venus host using pct exec (recommended)
pct exec 151 -- bash -c 'cd /opt/libretime && \
  docker compose start postgres && \
  sleep 10 && \
  docker compose exec -T postgres pg_restore -U libretime --verbose --clean --if-exists -d libretime < /tmp/libretime-db.dump'

# Method 2: From inside the container (if you're already SSH'd into the CT)
# First, enter the container: pct enter 151
# Then run:
#   cd /opt/libretime
#   docker compose start postgres
#   sleep 10
#   docker compose exec -T postgres pg_restore -U libretime --verbose --clean --if-exists -d libretime < /tmp/libretime-db.dump

# Note: For .sql files (plain text), use psql instead of pg_restore:
#   docker compose exec -T postgres psql -U libretime -d libretime < /tmp/libretime-db.sql

# Run database migrations to upgrade schema to 4.5.0
# Method 1: From Venus host using pct exec
pct exec 151 -- bash -c 'cd /opt/libretime && \
  docker compose up -d && \
  sleep 15 && \
  docker compose exec -T api libretime-api migrate'

# Method 2: From inside the container
#   cd /opt/libretime
#   docker compose up -d
#   sleep 15
#   docker compose exec -T api libretime-api migrate

# Verify database (88 warnings during restore are normal and safe)
# Method 1: From Venus host
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_files;"

# Method 2: From inside the container
#   docker compose exec -T postgres psql -U libretime -c "SELECT COUNT(*) FROM cc_files;"

# Should show your track count
```

### STEP 5: Transfer Media Files (~30-60 minutes, depends on size)

```bash
# Stop services before file transfer
# Method 1: From Venus host
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml stop

# Method 2: From inside the container
#   docker compose -f /opt/libretime/docker-compose.yml stop

# Transfer media files from Jupiter to Venus
# Option A: Direct rsync from Jupiter Docker volume (if Jupiter uses Docker)
rsync -avP --info=progress2 \
  root@jupiter:/var/lib/docker/volumes/libretime_storage/_data/ \
  /hdd-pool/container-data/libretime-media/aconcagua1/

# Option B: Rsync from Jupiter bare metal setup (non-Docker)
# Files are typically in /srv/libretime on Jupiter
rsync -avzP --info=progress2 -e 'ssh -p 22' \
  root@jupiter:/srv/libretime/ \
  /hdd-pool/migration-jupiter/aconcagua1/libretime/

# If you used Option B, move files from migration staging to container storage
# Check if files are in a nested 'libretime' directory
if [ -d /hdd-pool/migration-jupiter/aconcagua1/libretime ]; then
  mv /hdd-pool/migration-jupiter/aconcagua1/libretime/* \
     /hdd-pool/container-data/libretime-media/aconcagua1/
  rmdir /hdd-pool/migration-jupiter/aconcagua1/libretime
fi

# Fix any nested directory structure (happens with tar/rsync preserving paths)
# Check for /srv/libretime/srv/libretime nesting
if [ -d /hdd-pool/container-data/libretime-media/aconcagua1/srv/libretime ]; then
  mv /hdd-pool/container-data/libretime-media/aconcagua1/srv/libretime/* \
     /hdd-pool/container-data/libretime-media/aconcagua1/
  rmdir /hdd-pool/container-data/libretime-media/aconcagua1/srv/libretime
  rmdir /hdd-pool/container-data/libretime-media/aconcagua1/srv
fi

# Fix permissions on host (MUST run on Venus host, not inside container)
# Container UID 1000 maps to host UID 101000 in Proxmox
chown -R 101000:101000 /hdd-pool/container-data/libretime-media/aconcagua1/

# Verify directory structure and permissions
# On host
ls -lha /hdd-pool/container-data/libretime-media/aconcagua1/
# Should show: imported/ and organize/ directories owned by 101000:101000

# Verify from container perspective
# Method 1: From Venus host
pct exec 151 -- ls -lha /srv/libretime/
pct exec 151 -- df -h /srv/libretime

# Method 2: From inside the container
#   ls -lha /srv/libretime/
#   df -h /srv/libretime
# Should show: imported/ and organize/ owned by root:root (appears as 0:0 due to UID mapping)
```

### STEP 6: Start Services (~3 minutes)

```bash
# Start all services
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml up -d

# Wait for services to initialize
sleep 30

# Check all services are healthy
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml ps

# Check logs for errors
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml logs --tail 50
```

### STEP 7: Configure NPM & Public URL (~10 minutes)

```bash
# 1. In Nginx Proxy Manager:
# - Create new proxy host
# - Domain: djsclub.yourdomain.com
# - Forward to: 192.168.2.154:8080
# - Enable WebSockets
# - Request SSL certificate

# 2. Update LibreTime config.yml
pct exec 154 -- nano /opt/libretime/config.yml

# Update these lines:
#   public_url: https://djsclub.yourdomain.com
#   allowed_cors_origins: [https://djsclub.yourdomain.com]

# 3. Restart services
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml restart

# 4. Wait for restart
sleep 15
```

### STEP 8: Verify Migration (~5 minutes)

```bash
# 1. Test web interface
curl -I https://djsclub.yourdomain.com
# ✅ Should return HTTP 200

# 2. Login and verify:
# - https://djsclub.yourdomain.com
# - Login with admin credentials
# - Check Library → Shows tracks
# - Check Calendar → Shows schedules
# - Check Streams → Test stream playback

# 3. Verify storage usage
pct exec 154 -- df -h /srv/libretime
zfs list | grep djsclub

# 4. Check service health
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml ps
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 🔧 Common Issues & Fixes

### Issue: Services won't start after migration

```bash
# Check logs
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml logs

# Try full restart
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml down
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml up -d
```

### Issue: Permission errors on media files

```bash
# Fix all permissions
pct exec 154 -- chown -R 1000:1000 /srv/libretime/
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Issue: Database connection errors

```bash
# Restart PostgreSQL
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml restart postgres
sleep 10
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Issue: CORS errors after NPM setup

```bash
# Update config.yml with correct domain
pct exec 154 -- nano /opt/libretime/config.yml
# Add: allowed_cors_origins: [https://yourdomain.com]
pct exec 154 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 📊 Station-Specific Info

### djsclub (CT154)
- CTID: 154
- IP: 192.168.2.154
- Domain: djsclub.yourdomain.com
- Resources: 4 cores, 8GB RAM, 100GB storage
- Status: ⏳ PENDING

### aconcagua2 (CT152) - Reference
- CTID: 152
- IP: 192.168.2.152
- Domain: aconcagua2.yourdomain.com
- Resources: 4 cores, 8GB RAM, 50GB storage
- Status: ✅ MIGRATED (manual fix applied)

### aconcagua3 (CT153)
- CTID: 153
- IP: 192.168.2.153
- Domain: aconcagua3.yourdomain.com
- Resources: 4 cores, 8GB RAM, 100GB storage
- Status: ⏳ PENDING

### djsclub2 (CT154)
- CTID: 154
- IP: 192.168.2.154
- Domain: djsclub2.yourdomain.com
- Resources: 4 cores, 8GB RAM, 100GB storage
- Status: ⏳ PENDING

### djsclub (CT154)
- CTID: 154
- IP: 192.168.2.154
- Domain: djsclub.yourdomain.com
- Resources: 4 cores, 8GB RAM, 100GB storage
- Status: ⏳ PENDING

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## ✅ Success Checklist

After completing migration:

- [ ] Web interface accessible via HTTPS
- [ ] Can login with admin credentials
- [ ] All tracks visible in Library
- [ ] Playlists intact
- [ ] Calendar/schedule shows correctly
- [ ] Stream is playable
- [ ] Media files on HDD storage (verified)
- [ ] All Docker services running
- [ ] No errors in logs
- [ ] Database restored successfully
- [ ] CORS configured for public access
- [ ] NPM proxy configured with SSL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 📝 Notes

### What's Different from Manual Method:

**OLD (with manual fix):**
1. Deploy with RadioStack
2. **Enter container and edit docker-compose.yml** ⬅ MANUAL
3. **Restart services** ⬅ MANUAL  
4. **Remove Docker volume** ⬅ MANUAL
5. Transfer database
6. Transfer media
7. Configure NPM

**NEW (automatic):**
1. Deploy with RadioStack ⬅ **Includes automatic fix!**
2. Transfer database
3. Transfer media
4. Configure NPM

**Time Saved:** ~15 minutes per station
**Errors Prevented:** Manual editing mistakes

### Key Improvements:

✅ **No manual docker-compose.yml editing**
✅ **Automatic volume mount configuration**
✅ **Verification built into deployment**
✅ **Consistent configuration every time**
✅ **Faster deployment workflow**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 🔗 Additional Resources

**RadioStack Documentation:**
- docs/libretime.md - Complete LibreTime guide
- docs/storage-configuration.md - Storage architecture
- migration-docs/MIGRATION-QUICK-REFERENCE.md - Quick commands

**Your Migration Docs:**
- Google Drive: libretime-migration-radiostack.md
- Google Drive: libretime-migration-summary.md

**Support:**
- RadioStack Issues: https://github.com/TecnoSoul/RadioStack/issues
- LibreTime Docs: https://libretime.org/docs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Ready to migrate! Start with djsclub and verify the automatic fix works.** 🚀
