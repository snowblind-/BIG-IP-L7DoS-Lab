#!/usr/bin/env bash
# rate-filters.sh
#
# Creates BIG-IP rate filter traffic classes for use with LTM policies.
# Run via SSH on the BIG-IP or wrap with: ssh admin@<bigip> bash -s < rate-filters.sh
#
# Traffic classes define bandwidth ceilings applied in the TMM fast path.

echo "Creating rate filter traffic classes..."

# Strict — for high-value endpoints (/api/login, /checkout)
tmsh create ltm traffic-class rate-filter-strict \
    rate 1mbps \
    burst-size 64kb

# Medium — for search, API endpoints
tmsh create ltm traffic-class rate-filter-medium \
    rate 10mbps \
    burst-size 512kb

# Permissive — for general content, static assets
tmsh create ltm traffic-class rate-filter-permissive \
    rate 100mbps \
    burst-size 2mb

echo "Done. Verify with: tmsh list ltm traffic-class"
