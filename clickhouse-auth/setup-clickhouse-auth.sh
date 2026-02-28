#!/bin/bash
# setup-clickhouse-auth.sh - ClickHouse secure authentication setup
#
# Strategy:
#   default user: password required for ALL connections
#   localhost root: password auto-supplied from ~/.clickhouse-client/config.xml
#   network access: password must be specified explicitly
#
# Usage: sudo bash setup-clickhouse-auth.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}▶ $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
die()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

[ "$EUID" -ne 0 ] && die "Run as root: sudo bash $0"

CONFIG_FILE="/etc/clickhouse-server/users.d/network_security.xml"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   ClickHouse Authentication Setup                            ║"
echo "║                                                              ║"
echo "║   • default@localhost : password auto from client config     ║"
echo "║   • default@network   : password required explicitly         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ══════════════════════════════════════════════════════════════════
# 1. Password input
# ══════════════════════════════════════════════════════════════════
info "Set password for 'default' user"
echo ""

while true; do
    read -s -p "  Password: " PASSWORD
    echo ""
    read -s -p "  Confirm:  " PASSWORD_CONFIRM
    echo ""

    if [ -z "$PASSWORD" ]; then
        warn "Password cannot be empty!"
        echo ""
        continue
    fi

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        warn "Passwords do not match!"
        echo ""
        continue
    fi

    if [ ${#PASSWORD} -lt 8 ]; then
        warn "Password too short (minimum 8 characters)"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        [[ ! $REPLY =~ ^[Yy]$ ]] && continue
    fi

    break
done

ok "Password accepted"
echo ""

# Save password
echo "${PASSWORD}" > /root/.clickhouse_password
chmod 600 /root/.clickhouse_password
ok "Saved to /root/.clickhouse_password"
echo ""

# ══════════════════════════════════════════════════════════════════
# 2. Generate SHA256 hash
# ══════════════════════════════════════════════════════════════════
info "Generating SHA256 hash..."
PASSWORD_HASH=$(echo -n "${PASSWORD}" | sha256sum | awk '{print $1}')
ok "Hash: ${PASSWORD_HASH:0:16}...${PASSWORD_HASH: -8}"
echo ""

# ══════════════════════════════════════════════════════════════════
# 3. Create server config
# ══════════════════════════════════════════════════════════════════
info "Creating ${CONFIG_FILE}..."
mkdir -p "$(dirname $CONFIG_FILE)"

cat > "${CONFIG_FILE}" << EOF
<?xml version="1.0"?>
<!-- ClickHouse network security configuration -->
<!-- Generated: $(date) -->

<clickhouse>
    <users>
        <!-- DEFAULT USER: password required for ALL connections -->
        <!-- Localhost uses ~/.clickhouse-client/config.xml for seamless access -->
        <default>
            <password_sha256_hex>${PASSWORD_HASH}</password_sha256_hex>
            <networks>
                <ip>::/0</ip>
                <ip>0.0.0.0/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
        </default>
    </users>
</clickhouse>
EOF

chmod 640 "${CONFIG_FILE}"
chown clickhouse:clickhouse "${CONFIG_FILE}" 2>/dev/null || true
ok "Server config created: ${CONFIG_FILE}"
echo ""

# ══════════════════════════════════════════════════════════════════
# 4. Create client config for root (seamless localhost)
# ══════════════════════════════════════════════════════════════════
info "Creating /root/.clickhouse-client/config.xml..."
mkdir -p /root/.clickhouse-client

cat > /root/.clickhouse-client/config.xml << EOF
<?xml version="1.0"?>
<!-- ClickHouse client config - auto-supplies password for root -->
<config>
    <user>default</user>
    <password>${PASSWORD}</password>
</config>
EOF

chmod 600 /root/.clickhouse-client/config.xml
ok "Root client config created (password auto-supplied)"
echo ""

# ══════════════════════════════════════════════════════════════════
# 5. Create client config for clickhouse system user
# ══════════════════════════════════════════════════════════════════
if id clickhouse &>/dev/null; then
    CLICKHOUSE_HOME=$(eval echo ~clickhouse)
    mkdir -p "${CLICKHOUSE_HOME}/.clickhouse-client"
    cat > "${CLICKHOUSE_HOME}/.clickhouse-client/config.xml" << EOF
<?xml version="1.0"?>
<config>
    <user>default</user>
    <password>${PASSWORD}</password>
</config>
EOF
    chown -R clickhouse:clickhouse "${CLICKHOUSE_HOME}/.clickhouse-client"
    chmod 600 "${CLICKHOUSE_HOME}/.clickhouse-client/config.xml"
    ok "Config created for clickhouse system user"
    echo ""
fi

# ══════════════════════════════════════════════════════════════════
# 6. Backup existing config
# ══════════════════════════════════════════════════════════════════
BACKUP=""
if [ -f /etc/clickhouse-server/users.xml ]; then
    BACKUP="/etc/clickhouse-server/users.xml.backup-$(date +%Y%m%d%H%M%S)"
    cp /etc/clickhouse-server/users.xml "$BACKUP"
    info "Backup created: $BACKUP"
    echo ""
fi

# ══════════════════════════════════════════════════════════════════
# 7. Restart confirmation
# ══════════════════════════════════════════════════════════════════
warn "⚠️  About to restart ClickHouse server"
warn "⚠️  Network connections will require password after restart"
warn "⚠️  Localhost will auto-use password from client config"
echo ""
read -p "Continue with restart? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Cancelled. Config created but not applied."
    warn "To apply: systemctl restart clickhouse-server"
    exit 0
fi

info "Restarting ClickHouse server..."
systemctl restart clickhouse-server
sleep 3

if systemctl is-active --quiet clickhouse-server; then
    ok "ClickHouse restarted successfully"
else
    echo ""
    die "ClickHouse failed to start! Check: journalctl -xeu clickhouse-server\nRollback: mv ${BACKUP} /etc/clickhouse-server/users.xml && systemctl restart clickhouse-server"
fi
echo ""

# ══════════════════════════════════════════════════════════════════
# 8. Connection tests
# ══════════════════════════════════════════════════════════════════
info "Testing connections..."
echo ""

info "1️⃣  Localhost (password auto from config)..."
if clickhouse-client --query "SELECT 'localhost OK'" 2>/dev/null | grep -q "localhost OK"; then
    ok "Localhost works seamlessly"
else
    warn "Localhost test failed"
fi
echo ""

info "2️⃣  Network with explicit password..."
if clickhouse-client --host 127.0.0.1 --password "${PASSWORD}" --query "SELECT 'network OK'" 2>/dev/null | grep -q "network OK"; then
    ok "Network works with password"
else
    warn "Network test failed"
fi
echo ""

info "3️⃣  Network without password (should fail)..."
if clickhouse-client --host 127.0.0.1 --query "SELECT 1" 2>&1 | grep -qE "(Authentication failed|Password required|Wrong password)"; then
    ok "Network correctly requires password ✅"
else
    warn "Security: network should require password!"
fi
echo ""

# ══════════════════════════════════════════════════════════════════
# 9. Summary
# ══════════════════════════════════════════════════════════════════
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Setup Complete!                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Security status:"
echo "   • default user: password required for all connections"
echo "   • localhost (root): password auto-supplied from config"
echo "   • network: password must be specified"
echo ""
echo "📋 Usage:"
echo ""
echo "  # Localhost (as root, seamless):"
echo "  clickhouse-client --query 'SELECT 1'"
echo ""
echo "  # Network (explicit password):"
echo "  clickhouse-client --host ${SERVER_IP} --password '***'"
echo "  PASSWORD=\$(cat /root/.clickhouse_password)"
echo "  clickhouse-client --host ${SERVER_IP} --password \"\$PASSWORD\""
echo ""
echo "  # Python:"
echo "  client = clickhouse_connect.get_client("
echo "      host='${SERVER_IP}', user='default', password='***'"
echo "  )"
echo ""
echo "📄 Files:"
echo "   • Server config : ${CONFIG_FILE}"
echo "   • Client config : /root/.clickhouse-client/config.xml"
echo "   • Password      : /root/.clickhouse_password"
if [ -n "$BACKUP" ]; then
    echo "   • Backup        : ${BACKUP}"
fi
echo ""
warn "ACTION: Update all app connection strings to include password!"
echo ""
