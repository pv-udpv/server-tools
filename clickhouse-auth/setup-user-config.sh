#!/bin/bash
# setup-user-clickhouse-config.sh
# Create optimized ClickHouse client config for current user
# Usage: bash setup-user-clickhouse-config.sh

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${CYAN}▶ $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   ClickHouse User Client Config Setup                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Get password from root backup
if [ -f /root/.clickhouse_password ]; then
    info "Reading password from /root/.clickhouse_password..."
    PASSWORD=$(sudo cat /root/.clickhouse_password 2>/dev/null || echo "")
    if [ -z "$PASSWORD" ]; then
        warn "Could not read password file"
        read -s -p "Enter ClickHouse password: " PASSWORD
        echo ""
    else
        ok "Password loaded from root backup"
    fi
else
    info "No password file found at /root/.clickhouse_password"
    read -s -p "Enter ClickHouse password: " PASSWORD
    echo ""
fi

# Create client config directory
mkdir -p ~/.clickhouse-client
info "Creating ~/.clickhouse-client/config.xml..."

cat > ~/.clickhouse-client/config.xml << 'EOF'
<?xml version="1.0"?>
<!-- ClickHouse client config - auto-generated -->
<config>
    <!-- Authentication -->
    <user>default</user>
    <password>PASSWORD_PLACEHOLDER</password>
    
    <!-- Connection defaults -->
    <host>localhost</host>
    <port>9000</port>
    <database>default</database>
    
    <!-- History -->
    <history_file>~/.clickhouse-history</history_file>
    <history_max_entries>10000</history_max_entries>
    
    <!-- Prompt: [elapsed] database :) -->
    <prompt>[{elapsed}] {database} :) </prompt>
    
    <!-- Multiline mode: 0=off (Enter executes, use \\ for multiline) -->
    <multiline>0</multiline>
    
    <!-- Output format: PrettyCompact | TabSeparated | CSV | JSON | Vertical -->
    <format>PrettyCompact</format>
    
    <!-- Timeouts (seconds) -->
    <connect_timeout>10</connect_timeout>
    <receive_timeout>300</receive_timeout>
    <send_timeout>300</send_timeout>
    
    <!-- Enable progress bar -->
    <progress>1</progress>
    
    <!-- Autocomplete -->
    <suggest>
        <enable>1</enable>
    </suggest>
</config>
EOF

# Replace password placeholder
sed -i "s|PASSWORD_PLACEHOLDER|${PASSWORD}|g" ~/.clickhouse-client/config.xml

chmod 600 ~/.clickhouse-client/config.xml
ok "Config created: ~/.clickhouse-client/config.xml"
echo ""

# Create queries directory
mkdir -p ~/clickhouse-queries
info "Creating ~/clickhouse-queries/ for saved queries..."

# Sample queries
cat > ~/clickhouse-queries/top_tables.sql << 'SQLEOF'
-- Top 10 largest tables
SELECT
    database,
    name,
    formatReadableSize(total_bytes) AS size,
    formatReadableQuantity(total_rows) AS rows
FROM system.tables
WHERE total_bytes > 0
ORDER BY total_bytes DESC
LIMIT 10;
SQLEOF

cat > ~/clickhouse-queries/slow_queries.sql << 'SQLEOF'
-- 20 slowest queries today
SELECT
    query_id,
    query_duration_ms / 1000 AS duration_sec,
    formatReadableSize(memory_usage) AS memory,
    substring(query, 1, 100) AS query_preview
FROM system.query_log
WHERE type = 'QueryFinish'
  AND event_date = today()
ORDER BY query_duration_ms DESC
LIMIT 20;
SQLEOF

cat > ~/clickhouse-queries/disk_usage.sql << 'SQLEOF'
-- Disk usage by database
SELECT
    database,
    formatReadableSize(sum(total_bytes)) AS total_size,
    count() AS table_count
FROM system.tables
GROUP BY database
ORDER BY sum(total_bytes) DESC;
SQLEOF

ok "Sample queries created in ~/clickhouse-queries/"
echo ""

# Bash aliases
ALIAS_FILE=~/.clickhouse_aliases
cat > "$ALIAS_FILE" << 'ALIASEOF'
# ClickHouse aliases - source this in ~/.bashrc

# Client shortcuts
alias ch='clickhouse-client'
alias ch-local='clickhouse-client --host localhost'

# Query shortcuts
alias ch-top='clickhouse-client < ~/clickhouse-queries/top_tables.sql'
alias ch-slow='clickhouse-client < ~/clickhouse-queries/slow_queries.sql'
alias ch-disk='clickhouse-client < ~/clickhouse-queries/disk_usage.sql'

# History search (requires fzf)
if command -v fzf &> /dev/null; then
    alias ch-history='cat ~/.clickhouse-history | fzf'
fi

# Editor for multiline queries
export CLICKHOUSE_EDITOR=nano  # or vim, code, etc.
ALIASEOF

ok "Aliases created: $ALIAS_FILE"
echo ""

# Check if already sourced in bashrc
if ! grep -q "clickhouse_aliases" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# ClickHouse aliases" >> ~/.bashrc
    echo "[ -f ~/.clickhouse_aliases ] && source ~/.clickhouse_aliases" >> ~/.bashrc
    ok "Added to ~/.bashrc (restart shell or run: source ~/.bashrc)"
else
    info "Already in ~/.bashrc"
fi
echo ""

# Test connection
info "Testing connection..."
if clickhouse-client --query "SELECT 1" &>/dev/null; then
    ok "Connection successful!"
else
    warn "Connection test failed - check password"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Setup Complete!                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Next steps:"
echo ""
echo "  # Reload shell config:"
echo "  source ~/.bashrc"
echo ""
echo "  # Test:"
echo "  clickhouse-client"
echo "  ch-top        # Top 10 tables"
echo "  ch-slow       # Slowest queries"
echo "  ch-disk       # Disk usage"
echo ""
echo "  # Edit queries:"
echo "  nano ~/clickhouse-queries/my_query.sql"
echo "  clickhouse-client < ~/clickhouse-queries/my_query.sql"
echo ""
echo "📁 Files:"
echo "  • Config  : ~/.clickhouse-client/config.xml"
echo "  • Queries : ~/clickhouse-queries/"
echo "  • Aliases : ~/.clickhouse_aliases"
echo "  • History : ~/.clickhouse-history"
echo ""
