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
- ⏳ aconcagua1 (CT151) - NEXT
- ⏳ aconcagua3 (CT153)
- ⏳ djsclub2 (CT154)
- ⏳ txl (CT155)

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

## 🚀 Migration Steps (Per Station)

### STEP 1: Backup on Jupiter (~10 minutes)

```bash
# SSH to Jupiter
ssh root@jupiter

# Set variables (adjust for each station)
STATION_NAME="aconcagua1"
BACKUP_DATE=$(date +%Y%m%d)

# 1. Backup database
cd /opt/libretime
docker compose exec -T postgres pg_dump -U libretime libretime \
  > /root/libretime-backups/${STATION_NAME}-db-${BACKUP_DATE}.sql

# 2. Backup configuration
tar czf /root/libretime-backups/${STATION_NAME}-config-${BACKUP_DATE}.tar.gz \
  config.yml .env docker-compose.yml

# 3. Get database size (for reference)
ls -lh /root/libretime-backups/${STATION_NAME}-db-${BACKUP_DATE}.sql

# 4. Note media location
df -h /var/lib/docker/volumes/libretime_storage/_data
```

### STEP 2: Deploy on Venus (~5 minutes)

```bash
# SSH to Venus
ssh root@venus

# Navigate to RadioStack
cd /mnt/datos1/00-TecnoSoul/00-Servers/RadioStack

# Deploy LibreTime (with automatic volume fix!)
sudo ./scripts/platforms/libretime.sh \
  -i 151 \
  -n aconcagua1 \
  -c 4 \
  -m 8192 \
  -q 100G \
  -p 151

# Wait 3-5 minutes for deployment to complete
# You'll see: "✓ Volume mounts configured for HDD storage"
```

### STEP 3: Verify Volume Fix (~2 minutes)

```bash
# 1. Check docker-compose.yml has host mounts
pct exec 151 -- grep "/srv/libretime:/srv/libretime" /opt/libretime/docker-compose.yml
# ✅ Should show multiple matches

# 2. Verify storage is on HDD pool
pct exec 151 -- df -h /srv/libretime
# ✅ Should show: hdd-pool/container-data/libretime-media/aconcagua1

# 3. Confirm Docker volume doesn't exist
pct exec 151 -- docker volume ls | grep libretime_storage
# ✅ Should return nothing

# 4. Check all services are running
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml ps
# ✅ All services should show "Up"
```

### STEP 4: Transfer Database (~5 minutes)

```bash
# On Venus, transfer database from Jupiter
scp root@jupiter:/root/libretime-backups/aconcagua1-db-*.sql /tmp/

# Push to container
pct push 151 /tmp/aconcagua1-db-*.sql /root/libretime-db.sql

# Stop services before database restore
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml stop

# Restore database
pct exec 151 -- bash -c 'cd /opt/libretime && \
  docker compose start postgres && \
  sleep 10 && \
  docker compose exec -T postgres psql -U libretime < /root/libretime-db.sql'

# Verify database
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_files;"
# Should show your track count
```

### STEP 5: Transfer Media Files (~30-60 minutes, depends on size)

```bash
# Direct rsync from Jupiter to Venus HDD storage
rsync -avP --info=progress2 \
  root@jupiter:/var/lib/docker/volumes/libretime_storage/_data/ \
  /hdd-pool/container-data/libretime-media/aconcagua1/

# Fix permissions
pct exec 151 -- chown -R 1000:1000 /srv/libretime/

# Verify media is accessible
pct exec 151 -- ls -lh /srv/libretime/imported/ | head -10
pct exec 151 -- df -h /srv/libretime
```

### STEP 6: Start Services (~3 minutes)

```bash
# Start all services
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml up -d

# Wait for services to initialize
sleep 30

# Check all services are healthy
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml ps

# Check logs for errors
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml logs --tail 50
```

### STEP 7: Configure NPM & Public URL (~10 minutes)

```bash
# 1. In Nginx Proxy Manager:
# - Create new proxy host
# - Domain: aconcagua1.yourdomain.com
# - Forward to: 192.168.2.151:8080
# - Enable WebSockets
# - Request SSL certificate

# 2. Update LibreTime config.yml
pct exec 151 -- nano /opt/libretime/config.yml

# Update these lines:
#   public_url: https://aconcagua1.yourdomain.com
#   allowed_cors_origins: [https://aconcagua1.yourdomain.com]

# 3. Restart services
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml restart

# 4. Wait for restart
sleep 15
```

### STEP 8: Verify Migration (~5 minutes)

```bash
# 1. Test web interface
curl -I https://aconcagua1.yourdomain.com
# ✅ Should return HTTP 200

# 2. Login and verify:
# - https://aconcagua1.yourdomain.com
# - Login with admin credentials
# - Check Library → Shows tracks
# - Check Calendar → Shows schedules
# - Check Streams → Test stream playback

# 3. Verify storage usage
pct exec 151 -- df -h /srv/libretime
zfs list | grep aconcagua1

# 4. Check service health
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml ps
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 🔧 Common Issues & Fixes

### Issue: Services won't start after migration

```bash
# Check logs
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml logs

# Try full restart
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml down
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml up -d
```

### Issue: Permission errors on media files

```bash
# Fix all permissions
pct exec 151 -- chown -R 1000:1000 /srv/libretime/
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Issue: Database connection errors

```bash
# Restart PostgreSQL
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml restart postgres
sleep 10
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Issue: CORS errors after NPM setup

```bash
# Update config.yml with correct domain
pct exec 151 -- nano /opt/libretime/config.yml
# Add: allowed_cors_origins: [https://yourdomain.com]
pct exec 151 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 📊 Station-Specific Info

### aconcagua1 (CT151)
- CTID: 151
- IP: 192.168.2.151
- Domain: aconcagua1.yourdomain.com
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

### txl (CT155)
- CTID: 155
- IP: 192.168.2.155
- Domain: txl.yourdomain.com
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

**Ready to migrate! Start with aconcagua1 and verify the automatic fix works.** 🚀
