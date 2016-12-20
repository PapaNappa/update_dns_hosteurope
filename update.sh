#!/bin/bash

# update IPv6 addresses:
# 1. get the global address of this machine
# 2. extract the prefix
# 3. based on the DOMAINS6 array in the domains file, update every host using its own interface identifier

: ${CONFIG:=/etc/hosteurope-dyndns.conf}

source "$CONFIG" || {
    echo "Config file not found: $CONFIG"
    echo "You can change the path by setting the environment variable CONFIG."
    echo "See hosteurope-dyndns.conf.example for a sample config file."
    exit 1
}

: ${IPFILE:=/srv/ip}

UPDATE=0

# get global addresses of this machine
newIP4=$(dig +short myip.opendns.com '@resolver1.opendns.com')

newPREFIX6=$(ip -6 addr show dev ${INTERFACE} scope global | gawk '
    function expandIP6 (ip6,  blocks, block_count, missing_blocks, b, i, ip6_expanded) {
        # split ip in blocks
        blockcount = split(ip6, blocks, ":")
        missing_blocks = 8 - blockcount

        if (blocks[1] == "")
            ip6_expanded = "0"
        else
            ip6_expanded = blocks[1]

        # iterate over all blocks
        for (b = 2; b <= blockcount; b++) {
            if (length(blocks[b]) == 0) {
                # fill with zeros, *this* empty block, plus any missing blocks
                for (i = 0; i < missing_blocks + 1; i++) {
                    ip6_expanded = ip6_expanded ":0"
                }
            } else
                ip6_expanded = ip6_expanded ":" blocks[b]
        }

        return ip6_expanded
    }

    function getPrefix(ip6,   blocks, blockcount, digits, prefix_bits, prefix_part, d, b, prefix) {
        # split <ip>/<prefix_bits>
        split(ip6, blocks, "/")
        ip6 = blocks[1]
        prefix_bits = blocks[2]

        # split ip in blocks
        blockcount = split(ip6, blocks, ":")

        if (blockcount < 8)
            ip6 = expandIP6(ip6)

        prefix = blocks[1] # for simiplicity, assume prefix is at least 16
        prefix_bits = prefix_bits - 16

        for (b = 2; b <= 8; b++) {
            # add leading 0s ("1" gets "0001")
            for (d = 4 - length(blocks[b]); d >= 1; d--) {
                blocks[b] = "0" blocks[b]
            }

            prefix_part = ""
            for (d = 1; d <= 4; d++) {
                if (prefix_bits == 0)
                    break
                prefix_part = prefix_part substr(blocks[b], d, 1)
                prefix_bits = prefix_bits - 4
            }

            if (length(prefix_part) > 0)
                prefix = prefix ":" prefix_part

            if (prefix_bits == 0)
                break
        }

        return prefix
    }

    /inet6.*mngtmpaddr/ && $2 !~ /^f[cd]/{ print getPrefix($2); exit }
')

if [ -f "$IPFILE" ]; then
    source "$IPFILE"
    if [ "$IP4" != "$newIP4" ]; then
        UPDATE=1
    fi
    if [ "$PREFIX6" != "$newPREFIX6" ]; then
        UPDATE=1
    fi
else
    UPDATE=1
fi

if [ $UPDATE -ne 1 ]; then
    touch "$IPFILE" # as a log for the last check
    exit 0
fi

IP4=$newIP4
PREFIX6=$newPREFIX6

# make one call, so cookies do need to be saved temporarily
UPDATE_CALL=(curl -k --url "https://kis.hosteurope.de/?kdnummer=${USER_ID}&passwd=${PASSWORD}")

for HOSTID in "${DOMAINS4[@]}"; do
    UPDATE_CALL+=(
        --url "https://kis.hosteurope.de/administration/domainservices/index.php?record=0&pointer=${IP4}&menu=2&mode=autodns&domain=${DOMAIN}&submode=edit&truemode=host&hostid=${HOSTID}&submit=Update"
    )
done

for HOSTID in "${!DOMAINS6[@]}"; do
    IP6=${PREFIX6}${DOMAINS6[$HOSTID]}
    # record: 28=AAAA, 0=A
    UPDATE_CALL+=(
        --url "https://kis.hosteurope.de/administration/domainservices/index.php?record=28&pointer=${IP6}&menu=2&mode=autodns&domain=${DOMAIN}&submode=edit&truemode=host&hostid=${HOSTID}&submit=Update"
    )
done

UPDATE_CALL+=(
    --url "https://kis.hosteurope.de/?logout=1"
    -c /dev/null
)

"${UPDATE_CALL[@]}" > /dev/null 2> /dev/null || exit 1

# write to $IPFILE
echo "
# IP updated $(date)
PREFIX6=$PREFIX6
IP4=$IP4
" > "$IPFILE"

