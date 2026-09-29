#!/bin/bash
#
# create-lab-vips.sh
# Create the four L7DoS lab virtual servers in a SINGLE tmsh transaction
# (all-or-nothing), all fronting the UDF blueprint's EXISTING Hackazon_pool,
# then export the running config as an SCF.
#
# Run on the BIG-IP from the bash prompt (needs tmsh in PATH).
#
#   vs-lab-irules 10.1.10.55  | vs-lab-ltm 10.1.10.56
#   vs-lab-dos    10.1.10.63  | vs-lab-bot 10.1.10.74
#   pool: Hackazon_pool  (pre-existing, live member - NOT created here)
#
# The blueprint pre-builds demo VSs on .52/.54/.57/.58/.59/.61/.62/.65/.66, so
# the lab uses the free addresses above (.78 spare). Edit these to any FREE
# client-subnet address if your deployment differs:
#   tmsh list ltm virtual destination
#   tmsh list ltm virtual-address
#
set -uo pipefail

IRULES_VIP=10.1.10.55
LTM_VIP=10.1.10.56
DOS_VIP=10.1.10.63
BOT_VIP=10.1.10.74
POOL_NAME=Hackazon_pool
SCF_PATH=/var/local/scf/l7dos-lab.scf

# --- Pre-flight: the shared pool must already exist ---------------------------
if ! tmsh list ltm pool "$POOL_NAME" >/dev/null 2>&1; then
    echo "ERROR: pool '$POOL_NAME' not found. This lab reuses the blueprint pool."
    echo "       Check: tmsh list ltm pool"
    exit 1
fi

# --- Pre-flight: fail early (and cleanly) if an address is already in use -----
collision=0
for spec in "vs-lab-irules $IRULES_VIP" "vs-lab-ltm $LTM_VIP" \
            "vs-lab-dos $DOS_VIP" "vs-lab-bot $BOT_VIP"; do
    name=${spec% *}; addr=${spec#* }
    if tmsh list ltm virtual-address "$addr" >/dev/null 2>&1; then
        echo "COLLISION: $addr (intended for $name) is already in use."
        collision=1
    fi
done
if [ "$collision" -ne 0 ]; then
    echo "Aborting before any change. Pick free addresses (tmsh list ltm virtual destination)."
    exit 1
fi

# --- Atomic create: 4 VIPs in one cli transaction, all on Hackazon_pool ------
# An HTTP virtual needs a TCP profile under the HTTP profile, hence { tcp http }.
echo "== Creating VIPs in a single transaction (pool: $POOL_NAME) =="
tmsh <<TMSH
create cli transaction
create ltm virtual vs-lab-irules destination $IRULES_VIP:80 ip-protocol tcp pool $POOL_NAME profiles add { tcp http } source-address-translation { type automap }
create ltm virtual vs-lab-ltm destination $LTM_VIP:80 ip-protocol tcp pool $POOL_NAME profiles add { tcp http } source-address-translation { type automap }
create ltm virtual vs-lab-dos destination $DOS_VIP:80 ip-protocol tcp pool $POOL_NAME profiles add { tcp http } source-address-translation { type automap }
create ltm virtual vs-lab-bot destination $BOT_VIP:80 ip-protocol tcp pool $POOL_NAME profiles add { tcp http } source-address-translation { type automap }
submit cli transaction
TMSH

# --- Verify the transaction actually completed before persisting -------------
ok=1
for name in vs-lab-irules vs-lab-ltm vs-lab-dos vs-lab-bot; do
    tmsh list ltm virtual "$name" >/dev/null 2>&1 || { echo "MISSING: $name"; ok=0; }
done
if [ "$ok" -ne 1 ]; then
    echo "Transaction did not complete — NOT writing SCF. Nothing was saved."
    exit 1
fi

# --- Persist stored config, then write the full-config SCF snapshot ----------
echo "== Persisting stored config and writing SCF =="
tmsh save sys config
tmsh save sys config file "$SCF_PATH" no-passphrase

echo "Done. Created 4 VIPs on $POOL_NAME; SCF written to:"
echo "  ${SCF_PATH}  (and ${SCF_PATH}.tar)"
echo
echo "SCF is a WHOLE-device snapshot. Restore: tmsh load sys config file ${SCF_PATH}"
echo "Merge only these objects elsewhere: tmsh load sys config merge file <file>"
