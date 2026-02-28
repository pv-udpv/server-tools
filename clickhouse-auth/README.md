# clickhouse-auth

ClickHouse secure authentication setup: password-protected network access with seamless localhost experience.

## Files

| File | Description |
|------|-------------|
| `setup-clickhouse-auth.sh` | Server setup (root) — creates password, server config, restarts CH |
| `setup-user-config.sh` | User setup — creates client config with saved queries |
| `test-clickhouse-auth.sh` | Security tests |
| `queries/*.sql` | Sample queries (top tables, slow queries, disk usage) |

## Quick Start

```bash
# 1. Server setup (as root)
cd ~/server-tools/clickhouse-auth
sudo bash setup-clickhouse-auth.sh

# 2. User setup (as regular user)
bash setup-user-config.sh
source ~/.bashrc

# 3. Test
ch-top    # Top 10 tables
ch-slow   # Slowest queries
ch-disk   # Disk usage
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ClickHouse default user (password required everywhere)     │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴──────────┐
         │                      │
    Localhost               Network
         │                      │
┌────────▼────────┐   ┌────────▼─────────┐
│ ~/.clickhouse-  │   │ Explicit passwd  │
│ client/config   │   │ in connection    │
│ (auto-supplied) │   │ string           │
└─────────────────┘   └──────────────────┘
```

## Server Setup (Root)

`setup-clickhouse-auth.sh` creates:
- `/etc/clickhouse-server/users.d/network_security.xml` — server config with password hash
- `/root/.clickhouse-client/config.xml` — root client config
- `/root/.clickhouse_password` — plaintext backup

## User Setup

`setup-user-config.sh` creates:
- `~/.clickhouse-client/config.xml` — user client config with password
- `~/clickhouse-queries/*.sql` — sample queries
- `~/.clickhouse_aliases` — bash aliases
- Adds aliases to `~/.bashrc`

### Aliases Created

```bash
ch              # clickhouse-client
ch-top          # Top 10 largest tables
ch-slow         # Slowest queries today
ch-disk         # Disk usage by database
ch-history      # Search history with fzf (if installed)
```

## Usage Examples

### Localhost (seamless)

```bash
clickhouse-client --query "SELECT 1"
ch --query "SELECT count(*) FROM system.tables"
ch-top
```

### Network (explicit password)

```bash
PASSWORD=$(sudo cat /root/.clickhouse_password)
clickhouse-client --host YOUR_IP --password "$PASSWORD" --query "SELECT 1"
```

### Python

```python
import clickhouse_connect

client = clickhouse_connect.get_client(
    host='your.server.ip',
    user='default',
    password='your_password'
)

result = client.query("SELECT 1")
print(result.result_rows)
```

## Custom Queries

```bash
# Create new query
cat > ~/clickhouse-queries/my_query.sql << 'EOF'
SELECT
    database,
    count() AS table_count
FROM system.tables
GROUP BY database;
EOF

# Run it
clickhouse-client < ~/clickhouse-queries/my_query.sql

# Or create alias
echo "alias ch-my='clickhouse-client < ~/clickhouse-queries/my_query.sql'" >> ~/.clickhouse_aliases
source ~/.bashrc
ch-my
```

## Client Config Options

`~/.clickhouse-client/config.xml` supports:

| Option | Description | Default |
|--------|-------------|---------|
| `<user>` | Username | `default` |
| `<password>` | Plain text password | — |
| `<host>` | Server host | `localhost` |
| `<port>` | Server port | `9000` |
| `<database>` | Default database | `default` |
| `<history_file>` | History file path | `~/.clickhouse-history` |
| `<history_max_entries>` | Max history entries | `10000` |
| `<prompt>` | Interactive prompt | `[{elapsed}] {database} :)` |
| `<multiline>` | Multiline mode | `0` (off) |
| `<format>` | Output format | `PrettyCompact` |
| `<progress>` | Show progress bar | `1` (on) |

## Interactive Mode Tips

```bash
# Start interactive mode
clickhouse-client

# Commands:
\m          # Toggle multiline mode
\e          # Open editor ($CLICKHOUSE_EDITOR)
\q          # Quit
Ctrl+R      # Search history
↑/↓         # Navigate history

# Multiline with backslash (multiline=0)
SELECT \
  count(*) \
  FROM system.tables;
```

## Troubleshooting

### Password prompt appears

```bash
# Check client config exists
ls -la ~/.clickhouse-client/config.xml

# Verify password
cat ~/.clickhouse-client/config.xml

# Recreate config
bash setup-user-config.sh
```

### Auth failed

```bash
# Test with explicit password
PASSWORD=$(sudo cat /root/.clickhouse_password)
clickhouse-client --password "$PASSWORD" --query "SELECT 1"

# If works, client config is wrong
bash setup-user-config.sh
```

### Aliases not working

```bash
# Check if sourced
grep clickhouse_aliases ~/.bashrc

# Reload
source ~/.bashrc

# Or manually source
source ~/.clickhouse_aliases
```

## Security Notes

- Client config contains **plain text password** — protected with `chmod 600`
- Server config uses **SHA256 hash**
- Root access required to read `/root/.clickhouse_password`
- Each user should have their own `~/.clickhouse-client/config.xml`

## Files Location

| File | Purpose | Permissions |
|------|---------|-------------|
| `/etc/clickhouse-server/users.d/network_security.xml` | Server auth config | `640` |
| `/root/.clickhouse_password` | Password backup | `600` |
| `/root/.clickhouse-client/config.xml` | Root client config | `600` |
| `~/.clickhouse-client/config.xml` | User client config | `600` |
| `~/clickhouse-queries/*.sql` | Saved queries | `644` |
| `~/.clickhouse_aliases` | Bash aliases | `644` |
| `~/.clickhouse-history` | Query history | `600` |
