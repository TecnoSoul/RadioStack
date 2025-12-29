# Storage Configuration Fix - January 2025

## Bug Fix: AzuraCast Media Storage

### Issue
Prior to this fix, AzuraCast deployments via RadioStack would:
- ✅ Create ZFS dataset on HDD pool
- ✅ Mount HDD to container at `/var/azuracast`
- ❌ But fail to configure AzuraCast to use the mounted storage

**Result:** Media files were stored in Docker volumes on fast storage (NVMe/SSD) instead of the intended HDD storage, defeating the purpose of the two-tier storage architecture.

### Root Cause
The `install_azuracast()` function in [scripts/platforms/azuracast.sh](../scripts/platforms/azuracast.sh) did not modify AzuraCast's default `docker-compose.yml` after installation. The default configuration uses Docker named volumes instead of bind mounts to the HDD path.

### Fix Applied

**Modified File:** `scripts/platforms/azuracast.sh`

**Changes:**
1. Added post-installation storage configuration step
2. Automatically updates `docker-compose.yml` to use mounted HDD path
3. Creates stations directory with proper permissions (1000:1000)
4. Removes Docker volume definitions for station data
5. Restarts services with updated configuration

**Code Changes (lines 210-255):**
- Stop services before modification
- Backup original docker-compose.yml
- Create `/var/azuracast/stations` directory
- Replace `station_data:/var/azuracast/stations` with `/var/azuracast/stations:/var/azuracast/stations:rw`
- Remove `station_data:` from volumes section
- Restart services

### New Files

1. **Fix Script for Existing Deployments**
   - **Path:** `scripts/tools/fix-azuracast-storage.sh`
   - **Purpose:** Migrate existing deployments from Docker volumes to HDD storage
   - **Features:**
     - Data migration from Docker volume to HDD
     - Automatic docker-compose.yml updates
     - Backup creation before changes
     - Verification steps included

2. **Documentation**
   - **Path:** `docs/storage-configuration.md`
   - **Content:**
     - Explanation of two-tier storage architecture
     - Verification procedures
     - Troubleshooting guide
     - Manual configuration steps
     - Best practices

### Impact

**New Deployments:**
- All new AzuraCast deployments will automatically use HDD storage
- No manual intervention required
- Storage configuration verified during deployment

**Existing Deployments:**
- Run the fix script: `sudo ./scripts/tools/fix-azuracast-storage.sh --ctid CTID`
- Script migrates data without loss
- Safe to run on already-fixed deployments (idempotent)

### Verification

After deployment or fix, verify with:

```bash
# Check HDD mount (should show hdd-pool dataset)
pct exec CTID -- df -h /var/azuracast

# Check docker-compose.yml (should show /var/azuracast/stations)
pct exec CTID -- grep stations /var/azuracast/docker-compose.yml

# Upload media via web UI, then check storage
pct exec CTID -- ls -lh /var/azuracast/stations/*/media/
```

### Testing

**Test Scenario 1: Fresh Deployment**
```bash
sudo ./scripts/platforms/azuracast.sh \
  --ctid 999 \
  --name test-storage \
  --quota 100G

# Verify configuration
pct exec 999 -- grep "/var/azuracast/stations" /var/azuracast/docker-compose.yml
# Expected: Found

pct exec 999 -- docker volume ls | grep station_data
# Expected: Not found
```

**Test Scenario 2: Fix Existing Deployment**
```bash
# Assume container 232 has the old configuration
sudo ./scripts/tools/fix-azuracast-storage.sh --ctid 232

# Verify fix applied
pct exec 232 -- df -h /var/azuracast
pct exec 232 -- ls /var/azuracast/stations/
```

### Rollback Procedure

If issues occur, rollback is simple:

```bash
pct exec CTID -- bash -c '
  cd /var/azuracast
  docker compose down
  cp docker-compose.yml.bak docker-compose.yml
  docker compose up -d
'
```

### Related Issues

- Fixes the issue reported in container 232 (estudiorecords2)
- Addresses similar issues in containers 340, 341, 342, etc.
- Prevents future deployments from having this problem

### Performance Benefits

**Before Fix:**
- Media files on NVMe: Higher cost per GB
- Wasted fast storage capacity
- Limited media retention due to space constraints

**After Fix:**
- Media files on HDD: Lower cost per GB
- Fast storage freed for OS/DB operations
- Increased media retention capacity (300G-2T typical)

### Compatibility

- **Proxmox VE:** 8.0+, 9.0+
- **AzuraCast:** All versions (tested with latest stable)
- **RadioStack:** All versions (fix is backward compatible)

### Credits

**Identified by:** TecnoSoul deployment testing
**Fixed by:** Claude Sonnet 4.5 & TecnoSoul
**Date:** January 2025

### Additional Notes

- This fix is non-breaking - existing deployments continue to work
- The fix script is safe to run multiple times (idempotent)
- No data loss during migration process
- Automatic backups created before modifications
- Full documentation available in `docs/storage-configuration.md`
