#!/bin/bash
# test-clickhouse-auth.sh - Test ClickHouse authentication setup
# Usage: sudo bash test-clickhouse-auth.sh

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ PASS: $*${NC}"; }
fail() { echo -e "${RED}❌ FAIL: $*${NC}"; ALL_PASSED=false; }
info() { echo -e "${CYAN}▶ $*${NC}"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   ClickHouse Authentication Tests                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

ALL_PASSED=true

# Load password
PASSWORD=$(cat /root/.clickhouse_password 2>/dev/null || echo "")
if [ -z "$PASSWORD" ]; then
    fail "Password file not found: /root/.clickhouse_password"
    echo "Run setup first: sudo bash setup-clickhouse-auth.sh"
    exit 1
fi

info "1️⃣  Config files exist..."
[ -f /etc/clickhouse-server/users.d/network_security.xml ] \
    && ok "Server config exists" \
    || fail "Server config missing: /etc/clickhouse-server/users.d/network_security.xml"

[ -f /root/.clickhouse-client/config.xml ] \
    && ok "Root client config exists" \
    || fail "Root client config missing: /root/.clickhouse-client/config.xml"
echo ""

info "2️⃣  Localhost (password auto from config)..."
if clickhouse-client --query "SELECT 1" 2>/dev/null | grep -q "1"; then
    ok "Localhost works (password auto-supplied)"
else
    fail "Localhost access failed"
fi
echo ""

info "3️⃣  Network with correct password..."
if clickhouse-client --host 127.0.0.1 --password "${PASSWORD}" --query "SELECT 1" 2>/dev/null | grep -q "1"; then
    ok "Network access works with password"
else
    fail "Network access with password failed"
fi
echo ""

info "4️⃣  Network WITHOUT password (should fail)..."
if clickhouse-client --host 127.0.0.1 --query "SELECT 1" 2>&1 | grep -qE "(Authentication failed|Wrong password)"; then
    ok "Network correctly blocked without password"
else
    fail "SECURITY ISSUE: network should require password!"
fi
echo ""

info "5️⃣  Network with WRONG password (should fail)..."
if clickhouse-client --host 127.0.0.1 --password "wrong_pw_$(date +%s)" --query "SELECT 1" 2>&1 | grep -qE "(Authentication failed|Wrong password)"; then
    ok "Wrong password correctly rejected"
else
    fail "SECURITY ISSUE: wrong password should be rejected!"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
if [ "$ALL_PASSED" = true ]; then
    echo -e "║   ${GREEN}✅ All tests passed! Authentication is secure.${NC}           ║"
else
    echo -e "║   ${RED}❌ Some tests FAILED — check configuration!${NC}              ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"

$ALL_PASSED && exit 0 || exit 1
