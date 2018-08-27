#!/bin/bash

source core.sh

elevated_exec iptables -t nat -N TEST_CHAIN
elevated_exec iptables -t nat -F TEST_CHAIN

IP_LIST=./data/iplist.txt

for IP in `cat $IP_LIST`; do
    elevated_exec iptables -t nat -A TEST_CHAIN -d $IP -j DNAT --to 127.0.0.2
done
