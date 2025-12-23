# LibreTime Deployment Guide

Complete guide for deploying and managing LibreTime radio automation software with RadioStack.

## Overview

LibreTime is a open-source radio automation platform that provides:
- **Automated Scheduling** - Plan shows and playlists in advance
- **Live Broadcasting** - Master/live show support with Harbor inputs
- **Multiple Outputs** - Stream to Icecast, SHOUTcast, and other platforms
- **Web Playout** - Browser-based scheduling and management
- **Smart Playlists** - Dynamic playlist generation
- **Podcast Support** - Import and schedule podcast episodes

RadioStack deploys LibreTime 4.5.0 using Docker containers in optimized LXC containers.

## Quick Start

### Basic Deployment

```bash
# Deploy LibreTime with default settings
sudo ./scripts/platforms/libretime.sh -i 201 -n station1

# Access at http://192.168.2.201:8080
# Default credentials: admin / admin
```

### Custom Deployment

```bash
# Deploy with custom resources
sudo ./scripts/platforms/libretime.sh \
  -i 202 \
  -n fm-rock \
  -c 4 \
  -m 8192 \
  -q 500G \
  -p 152

# Parameters:
#   -i, --ctid       Container ID (200-299 range recommended)
#   -n, --name       Station name (alphanumeric, no spaces)
#   -c, --cores      CPU cores (default: 2)
#   -m, --memory     Memory in MB (default: 4092)
#   -q, --quota      Media storage quota (default: 30G)
#   -p, --ip-suffix  Last octet of IP (default: same as CTID)
```

## What Gets Deployed

RadioStack creates:

1. **LXC Container** (Debian 13)
   - Unprivileged container for security
   - Docker and Docker Compose installed
   - Optimized for LibreTime workloads

2. **ZFS Dataset** for media storage
   - Mounted at `/srv/libretime` in container
   - Recordsize: 128k (optimal for audio files)
   - Compression: lz4 (fast, good for media)

3. **LibreTime Services** (Docker Compose):
   - `postgres` - PostgreSQL database
   - `rabbitmq` - Message queue
   - `api` - Django REST API (Python)
   - `legacy` - Legacy PHP application
   - `nginx` - Web server (port 8080)
   - `icecast` - Streaming server (port 8000)
   - `playout` - Scheduling and automation
   - `liquidsoap` - Audio processing
   - `analyzer` - Media file analysis
   - `worker` - Background jobs

4. **Auto-start Configuration**
   - All containers restart automatically after reboot
   - Docker service enabled on boot

## Post-Deployment Configuration

### 1. Initial Login

1. Access `http://192.168.2.{CTID}:8080` in your browser
2. Login with default credentials:
   - Username: `admin`
   - Password: `admin`
3. **IMMEDIATELY** change the admin password:
   - Settings → Users → Edit admin user

### 2. Configure Public URL and CORS

For external access through a reverse proxy:

```bash
# Enter the container
sudo pct exec 201 -- bash

# Edit configuration
cd /opt/libretime
nano config.yml
```

Update these settings:

```yaml
general:
  public_url: https://radio.yourdomain.com  # Your public URL
  # ... other settings ...

# Add CORS configuration
allowed_cors_origins: [https://radio.yourdomain.com]
```

Restart services:

```bash
docker compose restart
exit
```

### 3. Configure Streaming Outputs

LibreTime includes a local Icecast server and can stream to remote servers.

#### Local Icecast (Included)

- URL: `http://192.168.2.{CTID}:8000`
- Mount point: `/main`
- Admin password: (auto-generated, check `.env` file)

#### Add Remote Icecast/SHOUTcast

1. Navigate to **Settings → Streams**
2. Click **Add New Stream**
3. Configure:
   - **Type**: Icecast or SHOUTcast
   - **Host**: Remote server hostname/IP
   - **Port**: 8000 (Icecast) or 8001 (SHOUTcast)
   - **Mount**: Your mount point (e.g., `/stream`)
   - **Password**: Source password
   - **Bitrate**: 128, 192, or 320 kbps
   - **Format**: MP3 or Opus

### 4. Upload Media Files

#### Via Web Interface

1. Go to **Library → Add Media**
2. Click **Upload** or drag files
3. Wait for analyzer to process files

#### Via Direct File Copy

```bash
# From Proxmox host
sudo pct push 201 /path/to/audio.mp3 /srv/libretime/imported/

# Set proper permissions
sudo pct exec 201 -- chown -R 1000:1000 /srv/libretime/imported/

# LibreTime will auto-import from watched folders
```

### 5. Create Your First Show

1. Navigate to **Calendar**
2. Click **+ New Show**
3. Configure:
   - **Name**: Show name
   - **Repeating**: Daily, weekly, or specific dates
   - **Time**: Start time and duration
   - **AutoDJ**: Enable for automatic playlist filling

4. Populate the show:
   - Go to **Show Builder**
   - Drag tracks from library
   - Or use **Smart Blocks** for auto-playlist

## Management Commands

### Container Management

```bash
# View container status
sudo pct status 201

# Enter container
sudo pct exec 201 -- bash

# Start/stop/restart container
sudo pct start 201
sudo pct stop 201
sudo pct restart 201
```

### Docker Services

```bash
# Check service status
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml ps

# View logs (all services)
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs

# View specific service logs
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs liquidsoap --tail 100
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs playout --tail 50

# Restart services
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml restart

# Restart specific service
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml restart liquidsoap
```

### Configuration Files

Located in `/opt/libretime/`:

```bash
config.yml              # Main LibreTime configuration
.env                    # Environment variables (passwords, etc.)
docker-compose.yml      # Docker services definition
nginx.conf              # Nginx web server configuration
```

## Troubleshooting

### No Audio / Stream Silent

**Symptoms**: Icecast shows connected but no audio

**Common Causes**:

1. **Playout service not running**
   ```bash
   sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs playout
   # Should show "PypoFetch: init complete"
   ```

2. **No shows scheduled**
   - Check Calendar for active shows
   - Verify show has content in Show Builder

3. **Liquidsoap errors**
   ```bash
   sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs liquidsoap
   # Look for connection errors or crashes
   ```

4. **File permissions**
   ```bash
   sudo pct exec 201 -- ls -la /srv/libretime/
   # Should be owned by UID 1000:1000
   ```

   Fix permissions:
   ```bash
   sudo pct exec 201 -- chown -R 1000:1000 /srv/libretime/
   ```

### Database Migration Errors

If you see "relation does not exist" errors:

```bash
# Run migrations manually
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml exec -T api libretime-api migrate

# Restart services
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Web Interface Not Accessible

**Check nginx status**:
```bash
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs nginx --tail 50
```

**Verify port mapping**:
```bash
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml ps
# nginx should show 0.0.0.0:8080->8080/tcp
```

**Test from inside container**:
```bash
sudo pct exec 201 -- curl -I http://localhost:8080
# Should return HTTP 200 or 401
```

### RabbitMQ Connection Errors

**Error**: `ValueError: Port could not be cast to integer`

**Cause**: Special characters in password (from old base64 encoding)

**Fix**: Already resolved in current version using hex encoding

If you encounter this on older deployments:
```bash
sudo ./scripts/tools/fix-libretime-rabbitmq.sh -i 201
```

### Services Not Starting After Reboot

**Check if Docker is enabled**:
```bash
sudo pct exec 201 -- systemctl status docker
```

**Enable Docker autostart**:
```bash
sudo pct exec 201 -- systemctl enable docker
```

**Verify restart policies**:
```bash
sudo pct exec 201 -- grep -A 1 "restart:" /opt/libretime/docker-compose.yml
# All services should have "restart: unless-stopped"
```

**Fix autostart** (if needed):
```bash
sudo ./scripts/tools/fix-libretime-autostart.sh -i 201
```

## Backup and Restore

### Manual Backup

```bash
# Backup configuration and database
sudo pct exec 201 -- bash -c '
  cd /opt/libretime
  mkdir -p /root/backups

  # Backup database
  docker compose exec -T postgres pg_dump -U libretime libretime > /root/backups/libretime-$(date +%Y%m%d).sql

  # Backup configuration
  tar czf /root/backups/libretime-config-$(date +%Y%m%d).tar.gz config.yml .env docker-compose.yml
'
```

### Automated Backups

Use Proxmox backup:
```bash
# Backup container (includes /opt/libretime)
vzdump 201 --compress zstd --mode snapshot --storage local

# Media is on separate ZFS dataset, snapshot it:
sudo zfs snapshot hdd-pool/container-data/libretime-media/station1@$(date +%Y%m%d)
```

### Restore from Backup

```bash
# Restore configuration
sudo pct exec 201 -- bash -c '
  cd /opt/libretime
  docker compose down

  # Restore database
  docker compose up -d postgres
  sleep 5
  cat /root/backups/libretime-20251223.sql | docker compose exec -T postgres psql -U libretime

  # Restore config
  tar xzf /root/backups/libretime-config-20251223.tar.gz

  # Restart all services
  docker compose up -d
'
```

## Updating LibreTime

### Check Current Version

```bash
sudo pct exec 201 -- cat /opt/libretime/.env | grep VERSION
```

### Update to Latest Version

```bash
# Enter container
sudo pct exec 201 -- bash
cd /opt/libretime

# Backup first!
docker compose exec -T postgres pg_dump -U libretime libretime > /root/libretime-pre-update.sql

# Update version in .env
nano .env
# Change: LIBRETIME_VERSION=4.5.0
# To:     LIBRETIME_VERSION=4.6.0  (or latest)

# Pull new images and restart
docker compose pull
docker compose up -d

# Run any new migrations
docker compose exec -T api libretime-api migrate

# Check logs
docker compose logs --tail 50
```

## Performance Tuning

### Adjust Container Resources

```bash
# Stop container
sudo pct stop 201

# Update resources
sudo pct set 201 --cores 6 --memory 8192

# Start container
sudo pct start 201
```

### Optimize Media Storage

```bash
# Increase ZFS quota
sudo zfs set quota=1T hdd-pool/container-data/libretime-media/station1

# Check usage
sudo zfs list | grep libretime-media
```

### Liquidsoap Tuning

Edit `/opt/libretime/config.yml`:

```yaml
stream:
  # Buffer size (seconds)
  buffer: 3.0

  # Queue length (items)
  queue_length: 10

  # Crossfade duration (seconds)
  crossfade: 2.0
```

## Advanced Configuration

### Custom Nginx Configuration

```bash
sudo pct exec 201 -- bash
cd /opt/libretime
nano nginx.conf

# Add custom locations, headers, etc.

docker compose restart nginx
```

### Multiple Stream Outputs

LibreTime supports unlimited stream outputs. Add in **Settings → Streams**:

- Different bitrates (64k for mobile, 320k for quality)
- Different formats (MP3, Opus, AAC)
- Multiple servers (primary + backup)
- Different mount points

### SSL/HTTPS with Reverse Proxy

LibreTime runs on HTTP internally. Use Nginx Proxy Manager or similar:

```
External Request → HTTPS → NPM → HTTP → LibreTime (port 8080)
```

NPM Configuration:
- **Scheme**: http
- **Forward Hostname**: 192.168.2.201
- **Forward Port**: 8080
- **Websockets Support**: On
- **SSL**: Request Let's Encrypt certificate

Remember to update `public_url` and `allowed_cors_origins` in config.yml!

## Resource Requirements

### Minimum (1-2 shows/day, small library)
- **CPU**: 2 cores
- **RAM**: 4GB
- **Storage**: 20GB quota

### Recommended (Active station, medium library)
- **CPU**: 4 cores
- **RAM**: 8GB
- **Storage**: 100GB+ quota

### High-Performance (24/7, large library, multiple streams)
- **CPU**: 6-8 cores
- **RAM**: 12-16GB
- **Storage**: 500GB+ quota

## Integration with Other Tools

### AutoDJ from Folder

Set up watched folders for auto-import:

```bash
# Create organized folders
sudo pct exec 201 -- mkdir -p /srv/libretime/{music,jingles,shows,podcasts}

# LibreTime will auto-import from these directories
# Configure in Settings → Media Folders
```

### API Access

LibreTime provides a REST API:

```bash
# Get API key from config.yml
API_KEY=$(sudo pct exec 201 -- grep "api_key:" /opt/libretime/config.yml | awk '{print $2}')

# Example: Get station info
curl -H "Authorization: Api-Key $API_KEY" \
  http://192.168.2.201:8080/api/v2/info
```

### Metadata for Stream Players

```bash
# Current playing track metadata
curl http://192.168.2.201:8080/api/live-info
```

## Known Issues and Limitations

### LibreTime 4.5.0 Specific

1. **Port 8080 Required**: LibreTime 4.5.0 uses port 8080 internally (not configurable)
2. **Python 3.10**: API service requires Python 3.10+
3. **Legacy PHP**: Some features still use old PHP codebase

### RadioStack Deployment

1. **First deployment takes 3-5 minutes**: Database migrations and Docker image pulls
2. **Hex passwords only**: Using base64 causes RabbitMQ parsing errors
3. **CORS must be configured**: Required for external access through reverse proxy

## Support and Resources

### Official LibreTime

- Website: https://libretime.org
- Documentation: https://libretime.org/docs
- GitHub: https://github.com/libretime/libretime
- Community: https://discourse.libretime.org

### RadioStack

- GitHub: https://github.com/TecnoSoul/RadioStack
- Issues: Report bugs specific to RadioStack deployment
- Changelog: See [CHANGELOG.md](../CHANGELOG.md) for recent fixes

## Migration from Manual Install

If you have an existing LibreTime manual installation:

1. **Backup existing data**:
   ```bash
   pg_dump libretime > libretime-backup.sql
   tar czf libretime-media.tar.gz /srv/libretime/
   ```

2. **Deploy new RadioStack container**

3. **Restore data**:
   ```bash
   # Copy backup files
   sudo pct push 201 libretime-backup.sql /root/
   sudo pct push 201 libretime-media.tar.gz /root/

   # Restore
   sudo pct exec 201 -- bash -c '
     cd /opt/libretime
     docker compose exec -T postgres psql -U libretime < /root/libretime-backup.sql
     tar xzf /root/libretime-media.tar.gz -C /srv/
     chown -R 1000:1000 /srv/libretime/
     docker compose restart
   '
   ```

4. **Update public_url** in config.yml to new domain

---

For more help, see [Troubleshooting Guide](troubleshooting.md) or open an issue on GitHub.
