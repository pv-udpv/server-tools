# server-tools

Server administration scripts, configs, and utilities.

## Contents

| Directory | Description |
|-----------|-------------|
| [`clickhouse-auth/`](clickhouse-auth/) | ClickHouse secure authentication setup |

## Quick deploy to server

```bash
# Clone and deploy to /home/user
git clone https://github.com/pv-udpv/server-tools.git
cp -r server-tools/clickhouse-auth ~/
cd ~/clickhouse-auth
sudo bash setup-clickhouse-auth.sh
```
