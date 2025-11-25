# RadioStack

**Unified Radio Platform Deployment System for Proxmox**

RadioStack is a comprehensive bash-based deployment framework for running professional radio broadcasting platforms (AzuraCast, LibreTime) on Proxmox VE. Built for sysadmins who want simple, powerful, and maintainable radio infrastructure.

## 🎯 Features

- 🚀 **One-command deployment** of AzuraCast and LibreTime
- 📦 **Optimized LXC containers** with proper resource allocation
- 💾 **Automatic ZFS management** with optimal recordsize/compression
- 🔄 **Bulk operations** - update all, backup all, status checks
- 📊 **Simple inventory** - CSV-based tracking of all stations
- 🎛️ **Multi-station support** - deploy dozens of stations on one host
- 🔧 **Production-tested** by TecnoSoul (20+ stations running)
- 📚 **Comprehensive docs** - from basics to advanced patterns

## 🚀 Quick Start
```bash
# Clone the repository
git clone https://github.com/matias-tecnosoul/radiostack.git
cd radiostack

# Install RadioStack
sudo ./install.sh

# Deploy AzuraCast station
radiostack deploy azuracast --ctid 340 --name main-station

# Deploy LibreTime station
radiostack deploy libretime --ctid 350 --name fm-rock

# Check status of all stations
radiostack status

# Update all AzuraCast instances
radiostack update azuracast --all
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
- [Deployment Guide](docs/deployment-guide.md) - Detailed deployment procedures
- [AzuraCast Guide](docs/azuracast.md) - AzuraCast-specific documentation
- [LibreTime Guide](docs/libretime.md) - LibreTime-specific documentation
- [Architecture Overview](docs/architecture.md) - System design and patterns
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [API Reference](docs/api-reference.md) - Script functions and parameters

## 🎯 Use Cases

### Small Station (1-2 streams)
```bash
radiostack deploy azuracast --ctid 340 --name station \
  --cores 4 --memory 8192 --quota 200G
```

### Medium Station (3-5 streams)
```bash
radiostack deploy azuracast --ctid 340 --name station \
  --cores 6 --memory 12288 --quota 500G
```

### Large Multi-Station Deployment
```bash
# Main station
radiostack deploy azuracast --ctid 340 --name main --quota 1T

# Regional stations
for region in north south east west; do
  radiostack deploy libretime --ctid 35$i --name "station-$region"
done
```

## 🔧 Platform Support

| Platform | Status | Container | VM | Notes |
|----------|--------|-----------|----|--------------------|
| AzuraCast | ✅ Stable | ✅ Yes | ⚠️ Experimental | Recommended: Container |
| LibreTime | ✅ Stable | ✅ Yes | ⚠️ Experimental | Recommended: Container |
| Icecast | 🚧 Planned | - | - | Standalone Icecast |
| Liquidsoap | 🚧 Planned | - | - | Standalone AutoDJ |

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup
```bash
git clone https://github.com/matias-tecnosoul/radiostack.git
cd radiostack
./scripts/dev-setup.sh
```

## 📊 Real-World Usage

RadioStack is used in production by:
- **TecnoSoul** - 20+ radio stations across Argentina
- Various community radio stations
- Educational broadcasting projects

## 🐛 Troubleshooting

Common issues and solutions are documented in [docs/troubleshooting.md](docs/troubleshooting.md).

Quick diagnostics:
```bash
# Check system requirements
radiostack check

# Validate container configuration
radiostack validate --ctid 340

# View logs
radiostack logs --ctid 340 --tail 50
```

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 👥 Credits

**Created by**: TecnoSoul Infrastructure Team & Claude AI


## 🔗 Links

- [GitHub Issues](https://github.com/matias-tecnosoul/radiostack/issues)
- [TecnoSoul](https://tecnosoul.com.ar)


If RadioStack helps you, please consider giving it a star! ⭐

---

**Built with ❤️ for the radio broadcasting community**
