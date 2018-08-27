#!/bin/bash

source core.sh

# trying to reproduce this issue

[ "$ETHDEV" ] || export ETHDEV=eth0

elevated_exec tc qdisc del dev $ETHDEV root
elevated_exec tc qdisc add dev $ETHDEV root handle 1: prio bands 3
elevated_exec tc qdisc add dev $ETHDEV parent 1:1 handle 10: pfifo limit 50
elevated_exec tc qdisc add dev $ETHDEV parent 1:2 handle 2: hfsc default 2
elevated_exec tc class add dev $ETHDEV parent 2: classid 2:1 hfsc sc rate 1024000kbit ul rate 1024000kbit
elevated_exec tc class add dev $ETHDEV parent 2: classid 2:2 hfsc sc rate 1024000kbit ul rate 1024000kbit
elevated_exec tc class add dev $ETHDEV parent 2:1 classid 2:1001 hfsc ls rate 0.1kbit ul rate 921600kbit
elevated_exec tc qdisc add dev $ETHDEV parent 2:1001 handle 1001: sfq perturb 10
elevated_exec tc class add dev $ETHDEV parent 2:1 classid 2:1002 hfsc sc umax 1500b dmax 60ms rate 307200kbit ul rate 1024000kbit
elevated_exec tc qdisc add dev $ETHDEV parent 2:1002 handle 1002: sfq perturb 10
elevated_exec tc class add dev $ETHDEV parent 2:1 classid 2:1003 hfsc sc umax 1500b dmax 40ms rate 614400kbit ul rate 1024000kbit
elevated_exec tc qdisc add dev $ETHDEV parent 2:1003 handle 1003: sfq perturb 10
elevated_exec tc class add dev $ETHDEV parent 2:1 classid 2:1000 hfsc ls rate 102400kbit ul rate 972800kbit
elevated_exec tc qdisc add dev $ETHDEV parent 2:1000 handle 1000: sfq perturb 10
