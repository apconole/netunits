#!/bin/bash
# Copyright (C) 2018, Red Hat, Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program.  If not, see <http://www.gnu.org/licenses/>.

__ipvs_exists_fn() {
    type "$1" 2>&1 | grep -q 'function' 2>/dev/null
}


if ! __ipvs_exists_fn 'with_temp_area'; then
    source ${SOURCE_LOCATION}core.sh
fi

ipvs_adm() {
    IPVS_ADM_BIN=""

    if get_bin IPVS_ADM_BIN ipvsadm ipvsadm ipvsadm; then
        $IPVS_ADM_BIN $@
        return 0
    else
        return 1
    fi
}

# Teardown all of the ipvs rules
common_teardown_ipvs() {
    delete_netns 'lb_backend_1'
    delete_netns 'lb_backend_2'
    delete_netns 'lb_balancer'
    delete_netns 'lb_client'
}

# setup 2 backend server namespaces, a load balancer namespace, and a client
# namespace
common_setup_ipvs() {
    common_teardown_ipvs

    # Create the two backends, and a load-balancer namespace
    make_netns 'lb_backend_1' || return 1
    make_netns 'lb_backend_2' || return 1
    make_netns 'lb_balancer' || return 1
    make_netns 'lb_client' || return 1

    create_veth_pair 'lbeth1' 'lbbe1_0' 'lb_backend_1' || return 1
    create_veth_pair 'lbeth1' 'lbbe2_0' 'lb_backend_2' || return 1
    create_veth_pair 'cleth1' 'lbcl0_0' 'lb_client' || return 1

    set_port_namespace 'lbbe1_0' 'lb_balancer' || return 1
    set_port_namespace 'lbbe2_0' 'lb_balancer' || return 1
    set_port_namespace 'lbcl0_0' 'lb_balancer' || return 1

    with_namespace 'lb_backend_1' ip link set lbeth1 up || return 1
    with_namespace 'lb_backend_2' ip link set lbeth1 up || return 1
    with_namespace 'lb_client' ip link set cleth1 up || return 1
    with_namespace 'lb_balancer' ip link set lbbe1_0 up || return 1
    with_namespace 'lb_balancer' ip link set lbbe2_0 up || return 1
    with_namespace 'lb_balancer' ip link set lbcl0_0 up || return 1

    with_namespace 'lb_client' ip addr add '172.31.110.2/24' dev cleth1 || return 1
    with_namespace 'lb_balancer' ip addr add '172.31.110.1/24' dev lbcl0_0 || return 1

    # create the bridge
    
    return 0
}



TESTID=0
RUNTIME=$(date -Iminutes)
export MASTER_LOG_FILE=ipvs-${RUNTIME}.log
for TEST in $(egrep ^test_ $0 | egrep '[({]' | sed 's@[{()}]*@@g'); do
    log_debug "Running $TEST"
    TESTID=$((TESTID+1))
    if [ "X$1" != "X" ]; then
        if [ "$1" != "$TEST" ]; then
            testAssertSkip "named $TEST"
        else
            $TEST
        fi
    else
        $TEST
    fi
done
report | tee iptables-${RUNTIME}.xml
