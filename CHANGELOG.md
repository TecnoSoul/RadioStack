# RadioStack Changelog

## [Unreleased] - 2025-12-23

### LibreTime 4.5.0 Deployment - Major Fixes

#### Fixed
- **Critical: Variable Expansion in Bash Heredoc** ([libretime.sh:237-317](scripts/platforms/libretime.sh#L237-L317))
  - Changed heredoc from double quotes to single quotes to prevent premature variable expansion
  - Fixed `$LIBRETIME_VERSION` injection using quote breaking: `'"$LIBRETIME_VERSION"'`
  - Removed all backslash escapes that were breaking wget and command execution
  - **Impact**: Downloads now work correctly with proper URL construction

- **Critical: Database Migration Command** ([libretime.sh:306-308](scripts/platforms/libretime.sh#L306-L308))
  - Updated from deprecated Laravel Artisan command to LibreTime 4.5.0 API command
  - Old (broken): `docker-compose exec -T libretime bash -c "cd /var/www/libretime && php artisan migrate --force"`
  - New (working): `docker-compose exec -T api libretime-api migrate`
  - Removed `|| true` to properly catch migration failures
  - **Impact**: Database tables now initialize correctly, fixing all 500/503 errors

- **Critical: Configuration File Generation** ([libretime.sh:275-290](scripts/platforms/libretime.sh#L275-L290))
  - Added automatic generation of required LibreTime configuration fields
  - `public_url`: Auto-detected from container IP address
  - `api_key`: Generated secure 32-byte hex key
  - `secret_key`: Generated secure 32-byte hex key
  - **Impact**: API authentication now works properly

- **Removed: Incorrect nginx.conf Modifications** ([libretime.sh:252-254](scripts/platforms/libretime.sh#L252-L254))
  - Removed sed commands that tried to change nginx port from 8080 to 80
  - LibreTime 4.5.0 already uses port 8080 internally (correct default)
  - **Impact**: nginx now uses the correct upstream configuration

- **Added: envsubst Installation** ([libretime.sh:244-246](scripts/platforms/libretime.sh#L244-L246))
  - Added `gettext-base` package for config template processing
  - Required for `envsubst < config.template.yml > config.yml` to work
  - **Impact**: Configuration files generate properly from templates

- **Improved: Service Initialization Timing** ([libretime.sh:302-316](scripts/platforms/libretime.sh#L302-L316))
  - Split initialization into proper phases:
    1. Wait 20s for PostgreSQL readiness
    2. Run migrations
    3. Wait 30s for service startup
    4. Restart services for clean connections
  - **Impact**: Services start reliably without connection errors

#### Technical Details

**Root Cause Analysis:**

1. **Bash Heredoc Quoting**: Using `bash -c "..."` caused the outer shell to interpret `\$VAR` and `\"`, breaking commands
   - Solution: Use `bash -c '...'` with selective variable injection

2. **LibreTime Version Compatibility**: Commands from LibreTime 3.x don't work in 4.5.0
   - Solution: Use the new Python-based API migration command

3. **Configuration Requirements**: LibreTime 4.5.0 requires `public_url`, `api_key`, and `secret_key` to be set
   - Solution: Auto-generate during deployment

**Testing:**
- ✅ Container creation and Docker installation
- ✅ File downloads (docker-compose.yml, config.template.yml, nginx.conf)
- ✅ Configuration generation with proper variables
- ✅ Database migration (50+ migrations applied successfully)
- ✅ All containers starting and staying healthy
- ✅ Web interface responding on port 8080
- ✅ No 500/503 errors in nginx or API logs

**Deployment Success:**
```bash
Container ID:   163
Station Name:   test3
IP Address:     192.168.2.163
Status:         ✅ All services healthy
Web Interface:  http://192.168.2.163:8080
Credentials:    admin / admin
```

### Changed
- Updated default LibreTime version from "stable" to "4.5.0" ([libretime.sh:36](scripts/platforms/libretime.sh#L36))
  - The "stable" tag redirects to GitHub releases page (404 for raw files)
  - Version 4.5.0 is the current stable release

### Notes for Future Versions
- When updating to LibreTime 5.x, verify the migration command syntax
- Monitor LibreTime GitHub for changes to docker-compose.yml structure
- The version tag should be a Git tag or branch name, not "stable" or "latest"

---

## Version Strategy

RadioStack uses direct version numbers rather than floating tags like "stable" or "latest" to ensure:
- Predictable deployments
- Easier troubleshooting
- Explicit version control
- Compatibility testing

Update `DEFAULT_LIBRETIME_VERSION` in [libretime.sh:36](scripts/platforms/libretime.sh#L36) when new releases are tested and verified.
