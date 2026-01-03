# LibreTime Migration Troubleshooting Notes

## Overview

This document captures lessons learned and solutions from troubleshooting the txl station migration, which encountered database corruption issues requiring a fresh deployment approach.

---

## Fresh Deployment Approach (When Database Restore Fails)

### When to Use This Approach

Use fresh deployment when:
- Database backup is corrupted or incompatible
- Database restore produces errors like "invalid command \N" or "syntax error"
- You're willing to sacrifice playlists/schedules to preserve media files
- The station can be reconfigured from scratch

### What You Lose vs Keep

**Lost:**
- All playlists and smart blocks
- All scheduled shows
- User accounts and permissions
- Station configuration (timezone, streaming settings, etc.)

**Kept:**
- All media files
- Clean, working LibreTime 4.5.0 installation

### Procedure

1. **Deploy fresh LibreTime instance**
   ```bash
   sudo ./scripts/platforms/libretime.sh -i <CTID> -n <station> -c 4 -m 8192 -q 100G -p <port>
   ```

2. **Transfer only media files** (skip database restore)
   ```bash
   # Stop services first
   pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml stop

   # Transfer media
   rsync -avzP root@jupiter:/path/to/media/ /hdd-pool/container-data/libretime-media/<station>/

   # Fix permissions (CRITICAL)
   chown -R 101000:101000 /hdd-pool/container-data/libretime-media/<station>/

   # Start services
   pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml up -d
   ```

3. **Run bulk import**
   ```bash
   pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T api \
     libretime-api bulk_import /srv/libretime/imported
   ```

---

## Database Issues & Solutions

### Issue: Hidden Tracks in LibreTime

**Symptom:** UI shows fewer tracks than database contains
- Example: UI shows 477 tracks, but `SELECT COUNT(*) FROM cc_files` returns 1,345

**Cause:** LibreTime uses a `hidden` column to hide:
1. Duplicate files (detected via MD5 checksum)
2. Orphaned database entries (metadata without actual files - `filepath IS NULL`)

**Investigation:**
```sql
-- Check total tracks
SELECT COUNT(*) FROM cc_files;

-- Check visible tracks (what UI shows)
SELECT COUNT(*) FROM cc_files WHERE hidden = false;

-- Check hidden tracks
SELECT COUNT(*) FROM cc_files WHERE hidden = true;

-- Find orphaned entries (metadata without files)
SELECT COUNT(*) FROM cc_files WHERE hidden = true AND filepath IS NULL;

-- Find actual duplicates
SELECT COUNT(*) FROM cc_files WHERE hidden = true AND filepath IS NOT NULL;
```

**Solution: Clean up orphaned entries**
```bash
# Delete orphaned database entries (hidden tracks with NULL filepath)
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "DELETE FROM cc_files WHERE hidden = true AND filepath IS NULL;"

# Verify cleanup
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_files;"
```

**Note:** Do NOT delete entries where `filepath IS NOT NULL` - these are legitimate duplicate detections by LibreTime's MD5 system.

---

## Storage Management

### Understanding LibreTime Storage Architecture

**Two separate storage areas:**

1. **Container Root Disk** (ZFS subvolume)
   - Path: `data/subvol-<CTID>-disk-0`
   - Purpose: System files, Docker images, LibreTime application
   - Typical size: 82G-132G
   - View: `pct exec <CTID> -- df -h /`

2. **Media Storage** (Bind mount from HDD pool)
   - Host path: `/hdd-pool/container-data/libretime-media/<station>/`
   - Container path: `/srv/libretime/`
   - Purpose: All media files (imported/, organize/)
   - Typical size: 200G-300G with quota
   - View: `pct exec <CTID> -- df -h /srv/libretime`

### Resizing Storage

**Resize Container Root Disk:**
```bash
# Method 1: Using pct resize
pct resize <CTID> rootfs +50G

# Method 2: Direct ZFS property (if pct resize doesn't update quota)
zfs set refquota=132G data/subvol-<CTID>-disk-0

# Verify
pct exec <CTID> -- df -h /
```

**Resize Media Storage:**
```bash
# Check current quota
zfs get quota hdd-pool/container-data/libretime-media/<station>

# Increase quota
zfs set quota=250G hdd-pool/container-data/libretime-media/<station>

# Remove quota (use all available space in hdd-pool)
zfs set quota=none hdd-pool/container-data/libretime-media/<station>

# Verify from container
pct exec <CTID> -- df -h /srv/libretime
```

**Important:** You CANNOT resize storage from Proxmox UI for the media mount point - it's a bind mount, not a disk. You must use ZFS commands on the host.

---

## File Count Discrepancies Explained

### Why File Counts Don't Match

When you see different file counts, here's what's happening:

**Original files on Jupiter:** 5,687 files
- Includes: audio files, images, text files, metadata, playlists, etc.

**Files after rsync to Venus:** 8,505 files
- Original 5,687 + temporary files created during transfer
- Non-audio files: 6,248 (images, .txt, .nfo, .m3u, etc.)
- Audio files: 2,257

**Database tracks after bulk_import:** 1,345
- LibreTime only imports recognized audio formats
- Skips duplicates (MD5 detection)
- Skips unsupported formats

**Visible tracks in UI:** 477
- LibreTime hides 868 as duplicates or orphaned entries
- Only shows unique, playable tracks with valid filepaths

**Takeaway:** This is normal. LibreTime is selective about what it imports and displays.

---

## Bulk Import Behavior

### What bulk_import Does

```bash
libretime-api bulk_import /srv/libretime/imported
```

1. **Scans directory recursively** for audio files
2. **Calculates MD5 checksum** for each file
3. **Checks for duplicates** - if MD5 exists, marks as hidden
4. **Validates audio format** - skips unsupported files
5. **Extracts metadata** - tags, duration, bitrate, etc.
6. **Creates database entry** in `cc_files` table
7. **Sets filepath** to track location

### Common Import Issues

**Files not imported:**
- Non-audio files (expected behavior)
- Corrupted audio files
- Unsupported formats (check LibreTime supported formats)

**Duplicates marked as hidden:**
- Intentional - prevents duplicate entries
- Based on MD5 checksum, not filename
- Keep the first import, hide subsequent ones

**Orphaned entries (filepath IS NULL):**
- Bug or interrupted import
- Safe to delete - these are metadata-only entries without actual files

---

## Permissions Issues

### Critical UID Mapping in Proxmox

**Inside container (what LibreTime sees):**
- Files owned by UID 1000 (appears as "root" or "libretime")
- Permissions: `drwxr-xr-x 1000:1000`

**On Proxmox host:**
- Same files owned by UID 101000 (mapped)
- Permissions: `drwxr-xr-x 101000:101000`

**Why this matters:**
- Container UID 1000 = Host UID 101000 (Proxmox UID mapping)
- You MUST use host UID (101000) when fixing permissions from host
- You use container UID (1000) when fixing from inside container

### Fixing Permissions

**From Proxmox host:**
```bash
chown -R 101000:101000 /hdd-pool/container-data/libretime-media/<station>/
```

**From inside container:**
```bash
pct exec <CTID> -- chown -R 1000:1000 /srv/libretime/
```

**Verify:**
```bash
# From host
ls -lha /hdd-pool/container-data/libretime-media/<station>/
# Should show: 101000:101000

# From container
pct exec <CTID> -- ls -lha /srv/libretime/
# Should show: 1000:1000 or root:root (both are correct due to mapping)
```

---

## Database Migration Alternatives

### Option A: Full Database Restore (Preferred)

**When to use:** Database backup is clean and compatible

```bash
# Transfer backup
pct push <CTID> /path/to/backup.dump /tmp/libretime-db.dump

# Stop services
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml stop

# Restore
pct exec <CTID> -- bash -c 'cd /opt/libretime && \
  docker compose start postgres && \
  sleep 10 && \
  docker compose exec -T postgres pg_restore -U libretime --verbose --clean --if-exists -d libretime < /tmp/libretime-db.dump'

# Run migrations
pct exec <CTID> -- bash -c 'cd /opt/libretime && \
  docker compose up -d && \
  sleep 15 && \
  docker compose exec -T api libretime-api migrate'
```

**Expected warnings:** ~88 warnings during restore are normal (missing sequences, dependencies)

### Option B: Hybrid Approach (Partial Restore)

**When to use:** Database partially corrupted but schema is salvageable

1. Restore schema without data
2. Manually restore specific tables that aren't corrupted
3. Run migrations
4. Use bulk_import for media files

**Note:** This approach is complex and error-prone. Usually better to use Option A or C.

### Option C: Fresh Deployment (Fallback)

**When to use:** Database completely corrupted or incompatible

See "Fresh Deployment Approach" section above.

---

## ZFS Storage Architecture

### Understanding ZFS Datasets

**Check all LibreTime datasets:**
```bash
zfs list | grep libretime
```

**Common layout:**
```
hdd-pool/container-data/libretime-media/station1   87.6G   112G  87.6G
hdd-pool/container-data/libretime-media/station2   45.2G   154G  45.2G
data/subvol-150-disk-0                             4.14G  77.9G  4.14G
data/subvol-151-disk-0                             3.82G  46.2G  3.82G
```

**Dataset properties:**
```bash
# View all properties
zfs get all hdd-pool/container-data/libretime-media/<station>

# Key properties for storage management
zfs get quota,refquota,reservation,refreservation <dataset>
```

**Quota vs Refquota:**
- `quota`: Limits total space (dataset + snapshots)
- `refquota`: Limits just the dataset (excludes snapshots)
- For LibreTime, `refquota` is what you typically want to manage

---

## Monitoring & Verification

### Health Check Commands

**Storage usage:**
```bash
# Container root disk
pct exec <CTID> -- df -h /

# Media storage
pct exec <CTID> -- df -h /srv/libretime

# ZFS pools
zfs list
zpool list
```

**Service health:**
```bash
# All services status
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml ps

# Recent logs (all services)
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml logs --tail 50

# Specific service logs
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml logs --tail 100 api
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml logs --tail 100 postgres
```

**Database health:**
```bash
# Track count
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_files;"

# Check for orphaned entries
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_files WHERE filepath IS NULL;"

# Check hidden tracks
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_files WHERE hidden = true;"
```

**File counts:**
```bash
# Total files in media directory
pct exec <CTID> -- find /srv/libretime -type f | wc -l

# Audio files only (common extensions)
pct exec <CTID> -- find /srv/libretime -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wav" \) | wc -l

# Directory sizes
pct exec <CTID> -- du -sh /srv/libretime/imported
pct exec <CTID> -- du -sh /srv/libretime/organize
```

---

## Common Pitfalls & Solutions

### Pitfall 1: Trying to resize media storage in Proxmox UI

**Problem:** Media storage is a bind mount, not a disk resource in Proxmox

**Solution:** Use ZFS commands on the host:
```bash
zfs set quota=<size>G hdd-pool/container-data/libretime-media/<station>
```

### Pitfall 2: Wrong UID when fixing permissions from host

**Problem:** Using UID 1000 instead of 101000 on Proxmox host

**Solution:** Always use UID 101000 from host:
```bash
chown -R 101000:101000 /hdd-pool/container-data/libretime-media/<station>/
```

### Pitfall 3: Deleting legitimate duplicate detections

**Problem:** Deleting ALL hidden tracks, including those with valid filepaths

**Solution:** Only delete orphaned entries (NULL filepath):
```sql
DELETE FROM cc_files WHERE hidden = true AND filepath IS NULL;
```

### Pitfall 4: Expecting all files to import

**Problem:** Non-audio files don't import, creating file count confusion

**Solution:** Understand that LibreTime only imports supported audio formats. Images, text files, playlists, etc. are stored but not in the database.

### Pitfall 5: Not running database migrations after restore

**Problem:** Restored database has old schema, incompatible with LibreTime 4.5.0

**Solution:** Always run migrations after restore:
```bash
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T api \
  libretime-api migrate
```

---

## Quick Reference Commands

### Storage Management
```bash
# Resize container root disk
pct resize <CTID> rootfs +50G
zfs set refquota=132G data/subvol-<CTID>-disk-0

# Resize media storage
zfs set quota=250G hdd-pool/container-data/libretime-media/<station>

# Check quotas
zfs get quota,refquota <dataset>
```

### Database Operations
```bash
# Count tracks
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_files;"

# Clean orphaned entries
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "DELETE FROM cc_files WHERE hidden = true AND filepath IS NULL;"

# Check hidden vs visible
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT hidden, COUNT(*) FROM cc_files GROUP BY hidden;"
```

### Service Management
```bash
# Restart all services
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml restart

# Restart specific service
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml restart postgres

# Check service status
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml ps

# View logs
pct exec <CTID> -- docker compose -f /opt/libretime/docker-compose.yml logs --tail 100
```

### Permissions Fix
```bash
# From host
chown -R 101000:101000 /hdd-pool/container-data/libretime-media/<station>/

# From container
pct exec <CTID> -- chown -R 1000:1000 /srv/libretime/
```

---

## Lessons Learned Summary

1. **Fresh deployment is a valid migration strategy** when database restore fails
2. **Hidden tracks are normal** - LibreTime uses MD5 to prevent duplicates
3. **File count discrepancies are expected** - not all files are audio files
4. **Orphaned database entries can be safely deleted** (filepath IS NULL)
5. **Two storage areas must be managed separately** - root disk vs media storage
6. **UID mapping matters** - use 101000 on host, 1000 in container
7. **ZFS quotas control media storage size** - not Proxmox UI
8. **Database migrations are mandatory** after restore to older versions
9. **bulk_import is selective** - only imports supported audio formats
10. **88 warnings during pg_restore are normal** and can be ignored

---

## Related Documentation

- Main migration guide: `final-libretime-migration-guide.md`
- RadioStack repository: https://github.com/TecnoSoul/RadioStack
- LibreTime docs: https://libretime.org/docs
- LibreTime 4.5.0 release notes: https://github.com/libretime/libretime/releases/tag/4.5.0

---

**Created:** 2026-01-03
**Station:** txl (CT150)
**Context:** Database corruption recovery, fresh deployment approach
