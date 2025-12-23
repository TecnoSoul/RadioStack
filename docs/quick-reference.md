# RadioStack Quick Reference

Quick command reference for common RadioStack operations.

## LibreTime Deployment

### Deploy New Station
```bash
# Basic deployment
sudo ./scripts/platforms/libretime.sh -i 201 -n station1

# Custom resources
sudo ./scripts/platforms/libretime.sh -i 202 -n fm-rock -c 4 -m 8192 -q 500G
```

### Access Station
- **Web Interface**: `http://192.168.2.{CTID}:8080`
- **Default Login**: admin / admin (change immediately!)
- **Icecast Stream**: `http://192.168.2.{CTID}:8000/main`

## Container Management

```bash
# Check status
sudo pct status 201

# Enter container
sudo pct exec 201 -- bash

# Start/stop/restart
sudo pct start 201
sudo pct stop 201
sudo pct restart 201

# View config
sudo pct config 201
```

## Docker Services

```bash
# All commands run inside container or via pct exec

# Service status
docker compose -f /opt/libretime/docker-compose.yml ps

# View all logs
docker compose -f /opt/libretime/docker-compose.yml logs --tail 100

# View specific service logs
docker compose -f /opt/libretime/docker-compose.yml logs liquidsoap --tail 50
docker compose -f /opt/libretime/docker-compose.yml logs playout --tail 50
docker compose -f /opt/libretime/docker-compose.yml logs nginx --tail 50

# Restart all services
docker compose -f /opt/libretime/docker-compose.yml restart

# Restart specific service
docker compose -f /opt/libretime/docker-compose.yml restart liquidsoap
```

## Configuration

### Main Configuration File
```bash
# Edit config.yml
sudo pct exec 201 -- nano /opt/libretime/config.yml

# Important settings:
# - public_url: Your public domain
# - allowed_cors_origins: [your public domain]
# - storage_path: /srv/libretime

# After changes, restart:
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Environment Variables
```bash
# View passwords and settings
sudo pct exec 201 -- cat /opt/libretime/.env

# Variables:
# - LIBRETIME_VERSION
# - POSTGRES_PASSWORD
# - RABBITMQ_DEFAULT_PASS
# - ICECAST_*_PASSWORD
```

## Troubleshooting

### No Audio Streaming

```bash
# Check playout service
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs playout
# Should see: "PypoFetch: init complete"

# Check liquidsoap
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs liquidsoap
# Should see: "Connecting mount main for source@icecast"

# Check file permissions
sudo pct exec 201 -- ls -la /srv/libretime/
# Should be: drwxr-xr-x 1000 1000

# Fix permissions if needed
sudo pct exec 201 -- chown -R 1000:1000 /srv/libretime/
```

### Web Interface Not Loading

```bash
# Check nginx
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs nginx

# Test from inside
sudo pct exec 201 -- curl -I http://localhost:8080
# Should return: HTTP/1.1 200 OK

# Check API
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml ps api
# Should show: Up (healthy)
```

### Database Errors

```bash
# Re-run migrations
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml exec -T api libretime-api migrate

# Restart services
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Services Not Starting After Reboot

```bash
# Check Docker status
sudo pct exec 201 -- systemctl status docker

# Enable Docker autostart
sudo pct exec 201 -- systemctl enable docker

# Check restart policies
sudo pct exec 201 -- grep "restart:" /opt/libretime/docker-compose.yml
# All services should have: restart: unless-stopped

# Fix autostart (if needed)
sudo ./scripts/tools/fix-libretime-autostart.sh -i 201
```

## Backup and Restore

### Backup

```bash
# Backup database
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  pg_dump -U libretime libretime > libretime-backup-$(date +%Y%m%d).sql

# Backup configuration
sudo pct exec 201 -- tar czf /root/libretime-config-$(date +%Y%m%d).tar.gz \
  -C /opt/libretime config.yml .env docker-compose.yml

# Snapshot media dataset
sudo zfs snapshot hdd-pool/container-data/libretime-media/station1@$(date +%Y%m%d)
```

### Restore

```bash
# Restore database
sudo pct push 201 libretime-backup-20251223.sql /root/
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime < /root/libretime-backup-20251223.sql

# Restore configuration
sudo pct push 201 libretime-config-20251223.tar.gz /root/
sudo pct exec 201 -- tar xzf /root/libretime-config-20251223.tar.gz -C /opt/libretime

# Restart
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

## Media Management

### Upload Media

```bash
# Upload single file
sudo pct push 201 /path/to/song.mp3 /srv/libretime/imported/

# Upload directory
sudo pct push 201 /path/to/music /srv/libretime/imported/

# Fix permissions after upload
sudo pct exec 201 -- chown -R 1000:1000 /srv/libretime/imported/
```

### Check Media Storage

```bash
# Check ZFS usage
sudo zfs list | grep libretime-media

# Check inside container
sudo pct exec 201 -- df -h /srv/libretime

# Increase quota
sudo zfs set quota=1T hdd-pool/container-data/libretime-media/station1
```

## Update LibreTime

```bash
# Enter container
sudo pct exec 201 -- bash
cd /opt/libretime

# Backup first!
docker compose exec -T postgres pg_dump -U libretime libretime > /root/backup-pre-update.sql

# Update version
nano .env
# Change LIBRETIME_VERSION=4.5.0 to newer version

# Pull and restart
docker compose pull
docker compose up -d

# Run migrations
docker compose exec -T api libretime-api migrate

# Check logs
docker compose logs --tail 50
```

## Performance Tuning

### Increase Container Resources

```bash
# Stop container
sudo pct stop 201

# Update CPU and memory
sudo pct set 201 --cores 6 --memory 12288

# Start container
sudo pct start 201
```

### Increase Media Storage

```bash
# Increase ZFS quota
sudo zfs set quota=1T hdd-pool/container-data/libretime-media/station1

# Verify
sudo zfs get quota hdd-pool/container-data/libretime-media/station1
```

## Useful Paths

### On Proxmox Host
```
RadioStack Installation:    ~/RadioStack
ZFS Media Dataset:          /hdd-pool/container-data/libretime-media/{station-name}
Container Config:           /etc/pve/lxc/{CTID}.conf
```

### Inside Container
```
LibreTime Installation:     /opt/libretime
Configuration:              /opt/libretime/config.yml
Environment Variables:      /opt/libretime/.env
Docker Compose:             /opt/libretime/docker-compose.yml
Media Storage:              /srv/libretime
Logs:                       /opt/libretime/ (via docker compose logs)
```

## Common Port Mapping

```
Host Port → Container Port → Service
-----------------------------------------
8080      → 8080           → LibreTime Web Interface
8000      → 8000           → Icecast Streaming Server
8001      → 8001           → Harbor Input (Master/Live)
8002      → 8002           → Harbor Input (Show)
```

## Quick Health Check

```bash
# One command to check everything
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml ps && \
sudo pct exec 201 -- curl -s -o /dev/null -w "HTTP: %{http_code}\n" http://localhost:8080 && \
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml exec -T postgres \
  psql -U libretime -c "SELECT COUNT(*) FROM cc_pref;" && \
echo "✅ All checks passed"
```

## Emergency Recovery

### Complete Service Restart

```bash
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml down
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml up -d
```

### Nuclear Option (Redeploy)

```bash
# DANGER: Destroys everything!
sudo pct stop 201
sudo pct destroy 201
sudo zfs destroy hdd-pool/container-data/libretime-media/station1

# Redeploy fresh
sudo ./scripts/platforms/libretime.sh -i 201 -n station1
```

## Getting Help

- **LibreTime Docs**: [docs/libretime.md](libretime.md)
- **Troubleshooting**: [docs/troubleshooting.md](troubleshooting.md)
- **Changelog**: [CHANGELOG.md](../CHANGELOG.md)
- **GitHub Issues**: Report bugs at https://github.com/TecnoSoul/RadioStack/issues

---

**Pro Tip**: Create shell aliases for common commands:

```bash
# Add to ~/.bashrc
alias lt-logs='docker compose -f /opt/libretime/docker-compose.yml logs'
alias lt-ps='docker compose -f /opt/libretime/docker-compose.yml ps'
alias lt-restart='docker compose -f /opt/libretime/docker-compose.yml restart'
```
