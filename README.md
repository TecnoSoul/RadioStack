# RadioStack

**Unified Radio Platform Deployment System for Proxmox**

RadioStack is a comprehensive bash-based deployment framework for running professional radio broadcasting platforms (AzuraCast, LibreTime) on Proxmox VE. Built for sysadmins who want standarized, maintainable radio infrastructure using IaC.

## 🎯 Features

- 🚀 **One-command deployment** of AzuraCast and LibreTime
- 📦 **Optimized LXC containers** with proper resource allocation
- 💾 **Automatic ZFS management** with optimal recordsize/compression
- 🔄 **Bulk operations** - update all, backup all, status checks
- 📊 **Simple inventory** - CSV-based tracking of all stations
- 🎛️ **Multi-station support** - deploy dozens of stations on one host
- 📚 **Comprehensive docs** - from basics to advanced patterns

## 🚀 Quick Start
```bash
# Clone the repository
git clone https://github.com/TecnoSoul/RadioStack.git
cd radiostack

# Deploy AzuraCast station
sudo ./scripts/platforms/azuracast.sh -i 340 -n main-station

# Deploy LibreTime station
sudo ./scripts/platforms/libretime.sh -i 350 -n fm-rock

# Check status of all stations
sudo ./scripts/tools/status.sh --all

# Update specific container
sudo ./scripts/tools/update.sh --ctid 340

# Backup container
sudo ./scripts/tools/backup.sh --ctid 340

# View logs
sudo ./scripts/tools/logs.sh --ctid 340 --follow
```

## 📋 Requirements

- **Proxmox VE**: 8.0+ or 9.0+
- **Operating System**: Debian-based Proxmox host
- **Storage**: ZFS pools (NVMe for OS + HDD for media recommended)
- **Templates**: Debian 12 or 13 LXC templates
- **Access**: Root or sudo access to Proxmox host
- **Network**: Internal network configured (e.g., 192.168.2.0/24)

## 🏗️ Architecture

RadioStack uses LXC containers with a two-tier storage strategy:
```
┌─────────────────────────────────────────────────────┐
│ Proxmox Host                                        │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐               │
│  │ NVMe Pool    │  │ HDD Pool     │               │
│  │ (data)       │  │ (hdd-pool)   │               │
│  │              │  │              │               │
│  │ - Container  │  │ - Media      │               │
│  │   OS         │  │   Libraries  │               │
│  │ - Docker     │  │ - Archives   │               │
│  │ - Databases  │  │ - Backups    │               │
│  └──────────────┘  └──────────────┘               │
│         │                  │                        │
│         ▼                  ▼                        │
│  ┌─────────────────────────────────┐               │
│  │ LXC Container (AzuraCast)       │               │
│  │ - ID: 340                       │               │
│  │ - IP: 192.168.2.140             │               │
│  │ - Root: 32GB (NVMe)            │               │
│  │ - Media: 500GB (HDD mount)     │               │
│  └─────────────────────────────────┘               │
└─────────────────────────────────────────────────────┘
```

## 📚 Documentation

- [Getting Started Guide](docs/getting-started.md) - Installation and first deployment
- [LibreTime Guide](docs/libretime.md) - LibreTime 4.5.0 deployment and management
- [Storage Configuration](docs/storage-configuration.md) - Two-tier storage architecture guide
- [Quick Reference](docs/quick-reference.md) - Common commands and operations
- [Testing Guide](TESTING.md) - Automated and manual testing procedures
- [Changelog](CHANGELOG.md) - Version history and fixes

## 🎯 Use Cases

### Small Station (1-2 streams)
```bash
./scripts/platforms/azuracast.sh -i 340 -n station \
  -c 4 -m 8192 -q 200G
```

### Medium Station (3-5 streams)
```bash
./scripts/platforms/azuracast.sh -i 340 -n station \
  -c 6 -m 12288 -q 500G
```

### Large Multi-Station Deployment
```bash
# Main station
./scripts/platforms/azuracast.sh -i 340 -n main -q 1T

# Regional stations
i=0
for region in north south east west; do
  ./scripts/platforms/libretime.sh -i 35$i -n "station-$region"
  ((i++))
done
```
## 📁 Repository Structure

```
radiostack/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── TESTING.md
├── docs/
│   ├── getting-started.md
│   ├── libretime.md
│   ├── quick-reference.md
│   └── storage-configuration.md
├── scripts/
│   ├── lib/
│   │   ├── common.sh              # Logging, validation, utilities
│   │   ├── container.sh           # LXC container operations
│   │   ├── storage.sh             # ZFS dataset management
│   │   └── inventory.sh           # Station tracking
│   ├── platforms/
│   │   ├── azuracast.sh           # AzuraCast deployment
│   │   ├── libretime.sh           # LibreTime deployment
│   │   └── deploy.sh              # Platform dispatcher
│   └── tools/
│       ├── status.sh              # View station status
│       ├── update.sh              # Update platforms
│       ├── backup.sh              # Backup operations
│       ├── remove.sh              # Remove stations
│       ├── info.sh                # Detailed information
│       └── logs.sh                # View logs
└── test-radiostack.sh             # Automated test suite
```


## 🔧 Platform Support

| Platform | Status | Container | VM | Notes |
|----------|--------|-----------|----|--------------------|
| AzuraCast | ✅ Stable | ✅ Yes | ⚠️ Experimental | Recommended: Container |
| LibreTime | ✅ Stable | ✅ Yes | ⚠️ Experimental | Recommended: Container |
| Icecast | 🚧 Planned | - | - | Standalone Icecast |
| Liquidsoap | 🚧 Planned | - | - | Standalone AutoDJ |

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.

### Development Setup
```bash
git clone https://github.com/TecnoSoul/RadioStack.git
cd RadioStack

# Run tests
sudo ./test-radiostack.sh

# Test deployment
sudo ./scripts/platforms/libretime.sh -i 999 -n test -c 2 -m 4096 -q 50G
```

## 📊 Real-World Usage

RadioStack is used in production by:
- **TecnoSoul** - 40+ radio stations across South America
- Various community radio stations
- Educational broadcasting projects

## 🐛 Troubleshooting

Quick diagnostics:
```bash
# Check status of all stations
sudo ./scripts/tools/status.sh --all

# Get detailed container information
sudo ./scripts/tools/info.sh --ctid 340

# View logs
sudo ./scripts/tools/logs.sh --ctid 340 --follow

# Run automated tests
sudo ./test-radiostack.sh
```

For specific issues:
- **LibreTime**: See [docs/libretime.md](docs/libretime.md) troubleshooting section
- **Storage**: See [docs/storage-configuration.md](docs/storage-configuration.md)
- **Quick commands**: See [docs/quick-reference.md](docs/quick-reference.md)

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 👥 Credits

**Created by**: TecnoSoul & Claude AI


## 🔗 Links

- [GitHub Issues](https://github.com/TecnoSoul/RadioStack/issues)
- [TecnoSoul](https://tecnosoul.com.ar)


If RadioStack helps you, please consider giving it a star! ⭐

---

**Built with ❤️ for the radio broadcasting community**
