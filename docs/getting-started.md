# Getting Started with RadioStack

This guide will walk you through deploying your first radio station with RadioStack.

## Prerequisites

Before using RadioStack, ensure your Proxmox host meets these requirements:

### System Requirements

- Proxmox VE 8.0+ or 9.0+
- Root or sudo access
- Internet connectivity for downloading packages

### Storage Requirements

RadioStack uses a two-tier storage strategy:

1. **Fast Storage (NVMe/SSD)** - for container OS and applications
   - Pool name: `data` (or your fast pool)
   - Minimum: 32GB per container

2. **Bulk Storage (HDD)** - for media libraries and archives
   - Pool name: `hdd-pool` (or your bulk pool)
   - Minimum: 50GB per station (500GB+ recommended for production)

### Network Requirements

- Internal network bridge configured (typically `vmbr1`)
- IP range available for containers (e.g., 192.168.2.0/24)
- Optional: Public IP or reverse proxy for external access

### Template Requirements

Download Debian 13 LXC template:
```bash
pveam update
pveam download local debian-13-standard_13.1-2_amd64.tar.zst
```

## Installation

### Clone Repository
```bash
cd ~
git clone https://github.com/TecnoSoul/RadioStack.git
cd RadioStack
```

That's it! RadioStack uses standalone scripts, no installation required.

### Verify Storage Pools

Check that your storage pools exist:
```bash
zpool list
```

You should see your fast pool (usually `data`) and HDD pool (usually `hdd-pool`).

## First Deployment

### Deploy Your First Station

Choose a platform and deploy:

**AzuraCast:**
```bash
sudo ./scripts/platforms/azuracast.sh -i 340 -n my-station
```

**LibreTime:**
```bash
sudo ./scripts/platforms/libretime.sh -i 350 -n my-station
```

The script will:
- Create LXC container
- Install Docker and Docker Compose
- Create ZFS dataset for media storage
- Install and configure the platform
- Start all services

Wait 3-5 minutes for the deployment to complete.

### Access Your Station

**AzuraCast:**
- URL: `http://192.168.2.340` (or your IP)
- Complete the web setup wizard to create your admin account

**LibreTime:**
- URL: `http://192.168.2.350:8080` (or your IP)
- Default login: `admin` / `admin`
- **Change the password immediately!**

## Common Operations

### Check Status
```bash
# All stations
sudo ./scripts/tools/status.sh --all

# Specific container
sudo ./scripts/tools/status.sh --ctid 340
```

### View Logs
```bash
# Follow logs in real-time
sudo ./scripts/tools/logs.sh --ctid 340 --follow

# View last 100 lines
sudo ./scripts/tools/logs.sh --ctid 340
```

### Get Container Information
```bash
sudo ./scripts/tools/info.sh --ctid 340
```

### Update Platform
```bash
# Update single station
sudo ./scripts/tools/update.sh --ctid 340

# Update all AzuraCast stations
sudo ./scripts/tools/update.sh --platform azuracast
```

### Backup Station
```bash
# Create backup
sudo ./scripts/tools/backup.sh --ctid 340

# List backups
sudo ./scripts/tools/backup.sh --list
```

### Remove Station
```bash
# Remove container (keep data)
sudo ./scripts/tools/remove.sh --ctid 340

# Remove container AND data
sudo ./scripts/tools/remove.sh --ctid 340 --data
```

## Deployment Options

### Custom Resources

Specify CPU, memory, and storage:

```bash
# AzuraCast with 8 cores, 16GB RAM, 1TB storage
sudo ./scripts/platforms/azuracast.sh \
  -i 341 \
  -n big-station \
  -c 8 \
  -m 16384 \
  -q 1T
```

### Custom IP Address

By default, the IP is `192.168.2.{CTID}`. To customize:

```bash
# Use IP 192.168.2.150 instead of 192.168.2.340
sudo ./scripts/platforms/azuracast.sh \
  -i 340 \
  -n my-station \
  -p 150
```

### Default Resources

**AzuraCast:**
- CPU: 6 cores
- Memory: 12GB
- Storage: 500GB

**LibreTime:**
- CPU: 4 cores
- Memory: 8GB
- Storage: 300GB

## Next Steps

### Configure External Access

For public access, set up a reverse proxy (like Nginx Proxy Manager):

1. Point your domain to your Proxmox host
2. Configure reverse proxy to forward to container IP
3. Set up SSL certificate (Let's Encrypt recommended)

**AzuraCast:**
- Forward `radio.yourdomain.com` → `http://192.168.2.340:80`

**LibreTime:**
- Forward `radio.yourdomain.com` → `http://192.168.2.350:8080`
- Update `public_url` in `/opt/libretime/config.yml`

### Deploy Multiple Stations

Deploy multiple stations in a loop:

```bash
# Deploy 5 AzuraCast stations
for i in {0..4}; do
  sudo ./scripts/platforms/azuracast.sh \
    -i $((340 + i)) \
    -n "station-$i"
done
```

### Set Up Backups

Create a backup script:

```bash
#!/bin/bash
# backup-all.sh - Daily backup script

sudo ./scripts/tools/backup.sh --platform azuracast
sudo ./scripts/tools/backup.sh --platform libretime

# Optional: ZFS snapshots
sudo zfs snapshot -r hdd-pool/container-data@$(date +%Y%m%d)
```

Add to cron:
```bash
# Daily backups at 3 AM
0 3 * * * /root/backup-all.sh
```

## Troubleshooting

### Container Won't Start

```bash
# Check container status
sudo pct status 340

# View container logs
sudo journalctl -u pve-container@340

# Try starting manually
sudo pct start 340
```

### Services Not Running

```bash
# Check Docker status
sudo pct exec 340 -- systemctl status docker

# Check Docker containers
sudo pct exec 340 -- docker ps
```

### Can't Access Web Interface

```bash
# Test from Proxmox host
ping 192.168.2.340
curl -I http://192.168.2.340

# Check from inside container
sudo pct exec 340 -- curl -I http://localhost
```

### Storage Issues

```bash
# Check ZFS datasets
sudo zfs list | grep container-data

# Check inside container
sudo pct exec 340 -- df -h
```

## Getting Help

### Documentation

- [LibreTime Guide](libretime.md) - Complete LibreTime deployment guide
- [Storage Configuration](storage-configuration.md) - Two-tier storage setup
- [Quick Reference](quick-reference.md) - Command cheat sheet
- [Testing Guide](../TESTING.md) - Testing procedures

### Run Tests

```bash
sudo ./test-radiostack.sh
```

### Community Support

- GitHub Issues: [Report bugs or request features](https://github.com/TecnoSoul/RadioStack/issues)
- Changelog: [CHANGELOG.md](../CHANGELOG.md) - Recent fixes and changes

## What's Next?

Now that you have your first station running:

1. **Upload media** - Add your music and content
2. **Configure streaming** - Set up Icecast/SHOUTcast outputs
3. **Create shows** - Schedule your programming
4. **Set up backups** - Protect your data
5. **Scale up** - Deploy more stations as needed

Happy broadcasting! 📻
