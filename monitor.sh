#!/bin/bash
pushd `dirname ${0}` >/dev/null || exit 1

# Get node variables
source ./mon_var.sh
# Get timestamp
now=$(date +%s%N)

# Get umeed version
version=$(${COS_BIN_NAME} version 2>&1)

# fill header
logentry="umee"
if [ -n "${COS_VALOPER}" ]; then logentry=$logentry",valoper=${COS_VALOPER}"; fi

# health is great by default
health=0

if [ -z "$version" ];
then 
    echo "ERROR: can't find UMEE binary">&2 ;
    health=1
    echo $logentry" health=$health $now"
else
    # Get node status
    status=$(curl -s localhost:$COS_PORT_RPC/status)
    if [ -z "$status" ];
    then
        echo "ERROR: can't connect to UMEE RPC">&2 ;
        health=2
        echo $logentry" health=$health $now"
    else
        # Get block height
        block_height=$(jq -r '.result.sync_info.latest_block_height' <<<$status)
        # Get block time
        latest_block_time=$(jq -r '.result.sync_info.latest_block_time' <<<$status)
        let "time_since_block = $(date +"%s") - $(date -d "$latest_block_time" +"%s")"
        latest_block_time=$(date -d "$latest_block_time" +"%s")
        # check time 
        if [ $time_since_block -gt 30 ]; then health=4; fi

        # Get catchup status
        catching_up=$(jq -r '.result.sync_info.catching_up' <<<$status)
        # Get Tendermint votiong power
        voting_power=$(jq -r '.result.validator_info.voting_power' <<<$status)
        # Peers count
        peers_num=$(curl -s localhost:${COS_PORT_RPC}/net_info | jq -r '.result.peers[].node_info | [.id, .moniker] | @csv' | wc -l)
        # Prepare metiric to out
        logentry=$logentry" ver=\"$version\",block_height=$block_height,catching_up=$catching_up,time_since_block=$time_since_block,latest_block_time=$latest_block_time,peers_num=$peers_num,voting_power=$voting_power"
        #
        # Get validator status
        val_status=$(${COS_BIN_NAME} query staking validator ${COS_VALOPER} --output json --node "tcp://localhost:${COS_PORT_RPC}")

        if [ -n "$val_status" ]
        then
            jailed=$(jq -r '.jailed' <<<$val_status)
            # Get all delegated to node tokens num
            delegated=$(jq -r '.tokens' <<<$val_status)
            # Get bonded status            
            if [ $(jq -r '.status' <<<$val_status) == "BOND_STATUS_BONDED" ]; then bonded=true; else bonded=false; fi
            # Missing blocks number in window (in UMEE slashing window size 100 blocks)
            bl_missed=$(jq -r '.missed_blocks_counter' <<<$($COS_BIN_NAME q slashing signing-info $($COS_BIN_NAME tendermint show-validator) -o json))
            # Get validator statistic
            list_limit=3000
            # Numbers of active validators
            val_active_numb=$(${COS_BIN_NAME} q staking validators -o json --limit=${list_limit} --node "tcp://localhost:${COS_PORT_RPC}" | 
            jq '.validators[] | select(.status=="BOND_STATUS_BONDED")' | jq -r ' .description.moniker' | wc -l)
            # Our stake value rank 
            val_rank=$(${COS_BIN_NAME} q staking validators -o json --limit=${list_limit} --node "tcp://localhost:${COS_PORT_RPC}" | \
            jq '.validators[] | select(.status=="BOND_STATUS_BONDED")' | jq -r ' .operator_address'  | sort -gr | nl |\
            grep  "${COS_VALOPER}" | awk '{print $1}')
            logentry="$logentry,jailed=$jailed,delegated=$delegated,bonded=$bonded,bl_missed=$bl_missed,val_active_numb=$val_active_numb"
            if [ -n "$val_rank" ]; then logentry="$logentry,val_rank=$val_rank"; fi
        else 
            health=3 # validator status problem
        fi
        echo "$logentry,health=$health $now"
        #echo "$logentry_header $logentry,health=$health $now"
    fi # umee rpc check
fi # umee binary check
