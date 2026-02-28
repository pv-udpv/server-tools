# clickhouse-auth

ClickHouse secure authentication setup: password-protected network access with seamless localhost experience.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  ClickHouse default user (password required everywhere)         │
└───────────────────┬─────────────────────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
    Localhost                Network
         │                     │
┌────────▼────────┐   ┌────────▼────────┐
│ ~/.clickhouse-  │   │ Explicit passwd │
│ client/config   │   │ in connection   │
│ (auto-supplied) │   │ string          │
└─────────────────┘   └─────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `setup-clickhouse-auth.sh` | Main setup — prompts password, creates configs, restarts CH |
| `test-clickhouse-auth.sh` | 5 security tests to verify setup |

## Quick Start

```bash
# 1. Deploy to server
git clone https://github.com/pv-udpv/server-tools.git
cp -r server-tools/clickhouse-auth ~/
cd ~/clickhouse-auth

# 2. Setup
sudo bash setup-clickhouse-auth.sh

# 3. Test
sudo bash test-clickhouse-auth.sh
```

## What the setup script does

1. Prompts for password (with confirmation)
2. Generates SHA256 hash for server config
3. Creates `/etc/clickhouse-server/users.d/network_security.xml`
4. Creates `/root/.clickhouse-client/config.xml` (auto-password for localhost)
5. Backs up existing `users.xml`
6. Asks for restart confirmation
7. Restarts ClickHouse
8. Tests all three access scenarios

## After Setup

```bash
# Localhost (root) — seamless, no typing required
clickhouse-client --query "SELECT 1"

# Network — explicit password required
PASSWORD=$(cat /root/.clickhouse_password)
clickhouse-client --host YOUR_IP --password "$PASSWORD" --query "SELECT 1"

# Python
import clickhouse_connect
client = clickhouse_connect.get_client(
    host='YOUR_IP',
    user='default',
    password='your_password'
)
```

## Client Config for Other Users

To give seamless localhost access to another user:

```bash
USERNAME=myuser
PASSWORD=$(cat /root/.clickhouse_password)

sudo mkdir -p /home/$USERNAME/.clickhouse-client
sudo tee /home/$USERNAME/.clickhouse-client/config.xml << EOF
<?xml version="1.0"?>
<config>
    <user>default</user>
    <password>$PASSWORD</password>
</config>
EOF
sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.clickhouse-client
sudo chmod 600 /home/$USERNAME/.clickhouse-client/config.xml
```

## Rollback

```bash
# Restore pre-setup backup
sudo mv /etc/clickhouse-server/users.xml.backup-YYYYMMDDHHMMSS /etc/clickhouse-server/users.xml
sudo rm /etc/clickhouse-server/users.d/network_security.xml
sudo systemctl restart clickhouse-server
```
