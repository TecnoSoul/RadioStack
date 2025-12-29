# AzuraCast Storage Configuration

## Overview

RadioStack uses a **two-tier storage architecture** for optimal performance and cost efficiency:

1. **Fast Storage (NVMe/SSD)**: Container OS, Docker, and databases
2. **Bulk Storage (HDD/ZFS)**: Media libraries, recordings, and archives

This guide explains how storage is configured and how to verify/fix the configuration.

## How It Works

### During Deployment

When you deploy AzuraCast using RadioStack, the following happens:

1. **ZFS Dataset Creation**
   ```bash
   zfs create -o recordsize=128k hdd-pool/container-data/azuracast-media/station-name
   zfs set quota=300G hdd-pool/container-data/azuracast-media/station-name
   ```

2. **Mount to Container**
   ```bash
   pct set CTID -mp0 /hdd-pool/container-data/azuracast-media/station-name,mp=/var/azuracast
   ```

3. **Configure AzuraCast**
   - AzuraCast's default `docker-compose.yml` uses Docker volumes
   - RadioStack automatically modifies it to use the mounted HDD path
   - Station data goes to `/var/azuracast/stations` (on HDD) instead of Docker volume (on NVMe)

## Verifying Storage Configuration

### Quick Check

Run these commands from your Proxmox host:

```bash
# Check if HDD is mounted (should show hdd-pool)
pct exec CTID -- df -h /var/azuracast

# Check docker-compose.yml configuration (should show /var/azuracast/stations)
pct exec CTID -- grep stations /var/azuracast/docker-compose.yml
```

### Expected Output

**Correct configuration** (using HDD):
```bash
$ pct exec 232 -- df -h /var/azuracast
Filesystem                                               Size  Used Avail Use% Mounted on
hdd-pool/container-data/azuracast-media/estudiorecords2  300G  2.5G  298G   1% /var/azuracast

$ pct exec 232 -- grep stations /var/azuracast/docker-compose.yml
- '/var/azuracast/stations:/var/azuracast/stations:rw'
```

**Incorrect configuration** (using Docker volume):
```bash
$ pct exec 232 -- grep stations /var/azuracast/docker-compose.yml
- 'station_data:/var/azuracast/stations'
```

### Detailed Verification

To see exactly where your media files are stored:

```bash
# Enter the container
pct enter CTID

# Check storage mounts
df -h

# Check docker-compose configuration
cat /var/azuracast/docker-compose.yml | grep -A2 -B2 stations

# Check where station data actually is
find /var/azuracast/stations -type f 2>/dev/null | head -5
find /var/lib/docker/volumes -name "*.mp3" 2>/dev/null | head -5
```

## Common Issues

### Issue: Media on Fast Storage Instead of HDD

**Symptoms:**
- Upload media files via AzuraCast web interface
- Run: `pct exec CTID -- df -h /var/azuracast` shows minimal usage
- Run: `pct exec CTID -- df -h /` shows high usage
- Files are in `/var/lib/docker/volumes/azuracast_station_data/`

**Cause:**
This can happen if:
1. You deployed before the storage fix was implemented (before 2024-01)
2. You manually installed AzuraCast without using RadioStack scripts
3. The deployment script failed during the storage configuration step

**Solution:**
Use the automated fix script:

```bash
sudo ./scripts/tools/fix-azuracast-storage.sh --ctid CTID
```

This script will:
1. Stop AzuraCast services safely
2. Migrate existing data from Docker volume to HDD
3. Update `docker-compose.yml` to use mounted path
4. Restart services
5. Clean up old Docker volume

### Issue: Permissions Errors

**Symptoms:**
- Can't upload files via web interface
- "Permission denied" errors in logs

**Solution:**
```bash
pct exec CTID -- chown -R 1000:1000 /var/azuracast/stations
pct exec CTID -- chmod -R 755 /var/azuracast/stations
```

### Issue: Storage Quota Exceeded

**Symptoms:**
- Can't upload more files
- "Disk quota exceeded" errors

**Check current usage:**
```bash
zfs list | grep azuracast-media
```

**Increase quota:**
```bash
# Example: Increase to 500G
zfs set quota=500G hdd-pool/container-data/azuracast-media/station-name
```

## Manual Storage Configuration

If you need to manually configure storage (e.g., for an existing deployment):

### Step 1: Stop Services
```bash
pct exec CTID -- bash -c "cd /var/azuracast && docker compose down"
```

### Step 2: Create Backup
```bash
pct exec CTID -- cp /var/azuracast/docker-compose.yml /var/azuracast/docker-compose.yml.backup
```

### Step 3: Migrate Data (if needed)
```bash
pct exec CTID -- bash -c '
    mkdir -p /var/azuracast/stations
    if docker volume inspect azuracast_station_data >/dev/null 2>&1; then
        TEMP=$(docker run -d -v azuracast_station_data:/source alpine tail -f /dev/null)
        docker cp $TEMP:/source/. /var/azuracast/stations/
        docker stop $TEMP
        docker rm $TEMP
    fi
    chown -R 1000:1000 /var/azuracast/stations
'
```

### Step 4: Update docker-compose.yml
```bash
pct exec CTID -- sed -i 's|station_data:/var/azuracast/stations|/var/azuracast/stations:/var/azuracast/stations:rw|g' /var/azuracast/docker-compose.yml

pct exec CTID -- sed -i '/^volumes:/,/^[^ ]/ { /station_data:/d }' /var/azuracast/docker-compose.yml
```

### Step 5: Restart Services
```bash
pct exec CTID -- bash -c "cd /var/azuracast && docker compose up -d"
```

### Step 6: Clean Up Old Volume
```bash
pct exec CTID -- docker volume rm azuracast_station_data
```

## Storage Best Practices

### 1. Monitor Storage Usage

Create a monitoring script:
```bash
#!/bin/bash
# Check all AzuraCast storage usage

echo "AzuraCast Storage Report"
echo "========================"
echo ""

zfs list -o name,used,avail,refer,quota | grep azuracast-media | while read line; do
    echo "$line"
done
```

### 2. Regular Cleanup

Remove old recordings and archives:
```bash
# Clean recordings older than 30 days
pct exec CTID -- find /var/azuracast/stations/*/recordings -name "*.mp3" -mtime +30 -delete

# Clean old backups
pct exec CTID -- find /var/azuracast/backups -name "*.zip" -mtime +90 -delete
```

### 3. Set Appropriate Quotas

**Small station** (1-2 streams):
- 200G - ~6 months of 24/7 recordings
- 500G - ~18 months of 24/7 recordings

**Medium station** (3-5 streams):
- 500G - ~3 months per stream
- 1T - ~6 months per stream

**Large station** (6+ streams):
- 1T - ~2 months per stream
- 2T+ - ~4+ months per stream

### 4. Compression Settings

RadioStack automatically sets optimal ZFS compression:
```bash
zfs set compression=lz4 hdd-pool/container-data/azuracast-media/station-name
zfs set recordsize=128k hdd-pool/container-data/azuracast-media/station-name
```

This provides:
- ~30% compression for audio files
- Optimal I/O performance for streaming
- Minimal CPU overhead

## Troubleshooting

### Storage Mount Not Showing

**Check LXC configuration:**
```bash
pct config CTID | grep mp0
```

**Expected output:**
```
mp0: /hdd-pool/container-data/azuracast-media/station-name,mp=/var/azuracast
```

**Fix if missing:**
```bash
pct set CTID -mp0 /hdd-pool/container-data/azuracast-media/station-name,mp=/var/azuracast
pct reboot CTID
```

### Docker Volume Still Exists

**List volumes:**
```bash
pct exec CTID -- docker volume ls | grep station
```

**Remove if not needed:**
```bash
pct exec CTID -- docker volume rm azuracast_station_data
```

### Performance Issues

**Check I/O stats:**
```bash
# On Proxmox host
zpool iostat hdd-pool 5

# Inside container
pct exec CTID -- iostat -x 5
```

**Optimize if needed:**
```bash
# Adjust ARC cache
echo "options zfs zfs_arc_max=8589934592" >> /etc/modprobe.d/zfs.conf  # 8GB

# Set ZFS caching for media
zfs set primarycache=metadata hdd-pool/container-data/azuracast-media
zfs set secondarycache=metadata hdd-pool/container-data/azuracast-media
```

## See Also

- [AzuraCast Documentation](https://docs.azuracast.com)
- [ZFS Best Practices](https://openzfs.github.io/openzfs-docs/)
- [Proxmox LXC Storage](https://pve.proxmox.com/wiki/Linux_Container#_storage)
