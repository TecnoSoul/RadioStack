# RadioStack Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2025-01-XX

First stable release of RadioStack - a comprehensive deployment framework for radio broadcasting platforms on Proxmox VE.

### Added

**Core Infrastructure**
- Complete modular architecture with `lib/`, `platforms/`, and `tools/` directories
- ZFS dataset management with optimal settings for media files (128k recordsize, lz4 compression)
- Inventory tracking system with CSV database and automatic backups
- Two-tier storage architecture (NVMe for OS/databases, HDD for media)
- Automated testing suite (test-radiostack.sh)

**Platform Support**
- AzuraCast deployment script with automatic storage configuration
- LibreTime 4.5.0 deployment script with full Docker Compose automation
- Automatic Docker and Docker Compose installation
- Auto-start configuration for services on reboot

**Management Tools**
- `status.sh` - View status of all stations or specific containers
- `update.sh` - Update platforms individually or in bulk
- `backup.sh` - Create container and application backups
- `remove.sh` - Safely remove stations with optional data cleanup
- `info.sh` - Display detailed container information
- `logs.sh` - View container and application logs with follow mode
- `fix-libretime-volumes.sh` - Migrate existing LibreTime deployments to HDD storage

**Documentation**
- Comprehensive LibreTime deployment guide (docs/libretime.md)
- Storage configuration guide with troubleshooting (docs/storage-configuration.md)
- Quick reference for common commands (docs/quick-reference.md)
- Getting started guide (docs/getting-started.md)
- Testing guide with automated and manual test procedures (TESTING.md)

### Fixed

**AzuraCast Storage Configuration (January 2025)**
- Fixed media files being stored in Docker volumes on fast storage instead of HDD
- Automatic configuration of docker-compose.yml to use HDD-mounted storage paths
- Created fix-azuracast-storage.sh script for migrating existing deployments
- Added verification steps to ensure proper storage configuration
- See docs/storage-configuration.md for complete details

**LibreTime Storage Configuration (January 2025)**
- **Critical: Fixed Docker volume mounts to use HDD storage** (libretime.sh:304-334)
  - Automatic configuration of docker-compose.yml during deployment
  - Replaces `libretime_storage:/srv/libretime` with `/srv/libretime:/srv/libretime`
  - Removes Docker volume definitions that store media on fast NVMe storage
  - Impact: Media files now correctly stored on HDD as intended by two-tier architecture
  - Eliminates need for manual docker-compose.yml editing after deployment

- Added `fix-libretime-volumes.sh` tool for existing deployments
  - Migrates existing LibreTime deployments from Docker volumes to HDD mounts
  - Automated backup creation and verification
  - Safe to run on already-fixed deployments (idempotent)

**LibreTime 4.5.0 Deployment (December 2024)**
- **Critical: Fixed variable expansion in Bash heredoc** (libretime.sh:237-317)
  - Changed from double quotes to single quotes to prevent premature expansion
  - Fixed `$LIBRETIME_VERSION` injection using quote breaking
  - Impact: Downloads now work correctly with proper URL construction

- **Critical: Fixed database migration command** (libretime.sh:306-308)
  - Updated from deprecated Laravel Artisan to LibreTime 4.5.0 API command
  - Impact: Database tables now initialize correctly, fixing all 500/503 errors

- **Critical: Added configuration file generation** (libretime.sh:275-290)
  - Auto-generates: `public_url`, `api_key`, `secret_key`
  - Uses hex encoding for passwords (avoiding URL-breaking characters)
  - Impact: API authentication now works properly

- Added envsubst installation for config template processing
- Improved service initialization timing with proper wait phases

### Changed
- Updated default LibreTime version from "stable" to "4.5.0"
- Uses direct version numbers for predictable deployments

### Testing
- ✅ Container creation and Docker installation verified
- ✅ Database migrations tested (50+ migrations applied successfully)
- ✅ All containers starting and staying healthy
- ✅ Web interfaces accessible
- ✅ Audio streaming functionality verified
- ✅ Auto-start on reboot confirmed
- ✅ LibreTime volume fix tested on production deployment (aconcagua2/CT152)

### Technical Details

**LibreTime Deployment Solutions:**
1. **Bash Heredoc Quoting**: Use `bash -c '...'` with selective variable injection instead of `bash -c "..."`
2. **LibreTime Version Compatibility**: Use new Python-based API migration command for 4.5.0+
3. **Configuration Requirements**: Auto-generate required fields during deployment
4. **Volume Mount Fix**: Automatically configure docker-compose.yml to use host mounts instead of Docker volumes

**Storage Architecture:**
- Container OS on fast storage (NVMe/SSD pool)
- Media files on bulk storage (HDD ZFS pool with compression)
- Automatic bind mount configuration for both AzuraCast and LibreTime
- Proper UID mapping for unprivileged containers (100000:100000)

### Notes for Future Versions
- When updating to LibreTime 5.x, verify the migration command syntax
- Monitor LibreTime GitHub for changes to docker-compose.yml structure
- Use Git tag or branch name for versions, not "stable" or "latest"
- The volume fix applies to both new deployments and existing installations

### Credits
- **Created by**: TecnoSoul & Claude AI
- **Tested in production**: 40+ radio stations across South America
- **License**: MIT

---

## Version Strategy

RadioStack uses direct version numbers rather than floating tags to ensure:
- Predictable deployments
- Easier troubleshooting
- Explicit version control
- Compatibility testing
