#!/bin/bash
# Copyright (C) 2016, Red Hat, Inc.
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

__openvswitch_exists_fn() {
    type "$1" 2>&1 | grep -q 'function' 2>/dev/null
}


if ! __openvswitch_exists_fn 'with_temp_area'; then
    source ${SOURCE_LOCATION}core.sh
fi


export MASTER_LOG_FILE=openvswitch-$(date -Iminutes).log

if [ "X$OVS_PREFIX" == "X" ]; then
    OVS_PREFIX=/usr
fi

build_openvswitch_from_version() {
    echo "not right now"
    return 0
}

start_openvswitch() {
    if ! is_process_running "ovs-vswitchd"; then
        log_info "Attempting to start openvswitch"
        if ! elevated_exec ${OVS_PREFIX}/share/openvswitch/scripts/ovs-ctl start; then
            log_err "Unable to start.  Returning failure."
            return 1
        fi
    fi

    for bridge in $(elevated_exec ${OVS_PREFIX}/bin/ovs-vsctl show | grep Bridge)
    do
        brname=$(echo $bridge | cut -d" " -f2 | sed s@\"@@g)
        elevated_exec ${OVS_PREFIX}/bin/ovs-vsctl del-br $brname
        log_info "Deleted bridge $brname"
    done
    return 0
}

stop_openvswitch() {
    for bridge in $(elevated_exec ${OVS_PREFIX}/bin/ovs-vsctl show | grep Bridge | cut -d\" -f2)
    do
        brname=$(echo $bridge)
        elevated_exec ${OVS_PREFIX}/bin/ovs-vsctl del-br $brname
        log_info "Deleted bridge $brname"
    done
    elevated_exec ${OVS_PREFIX}/share/openvswitch/scripts/ovs-ctl stop
    return 0
}

OvsTestAssertFailure() {
    testAssertFailure $@
    stop_openvswitch
    return 1
}

test_openvswitch_starts_and_stops() {
    if ! start_openvswitch; then
        testAssertFailure "Failure - unable to start ovs"
        return 1
    fi
    if ! stop_openvswitch; then
        testAssertFailure "Failure - unable to stop ovs"
    fi
    testAssertPass
    return 0
}

ovs_vsctl() {
    log_info "execute ovs-vsctl $str"
    elevated_exec ${OVS_PREFIX}/bin/ovs-vsctl $@
    return $?
}

create_ovs_bridge() {
    brname=$1
    shift

    str="add-br $brname"
    if [[ "$1" != "" ]]; then
        str=$str -- set Bridge $brname datapath_type=$1
    fi

    ovs_vsctl $str
    return $?
}

attach_veth_ovs_bridge() {
    brname=$1
    shift
    
    namespace=$1
    shift

    veth_name=$1
    shift

    find_br=$(ovs_vsctl "list" | grep -o $brname)
    if [ "$find_br" != "$brname" ]; then
        create_ovs_bridge "$brname"
    fi

    create_veth_pair "${veth_name}" "ovstest_${veth_name}" "$namespace"
    
    ovs_vsctl add-port "$brname" "ovstest_${veth_name}"
}

test_openvswitch_ns_ping() {
    start_openvswitch || OvsTestAssertFailure "Unable to start ovs"
    if [ $? == 1 ]; then
        return 1
    fi

    create_ovs_bridge "tbr0" || OvsTestAssertFailure "Unable to setup bridge"
    if [ $? == 1 ]; then
        return 1
    fi

    make_netns ns0 || OvsTestAssertFailure "Unable to create namespace ns0"
    if [ $? == 1 ]; then
        return 1
    fi

    make_netns ns1 || OvsTestAssertFailure "Unable to create ns1"
    if [ $? == 1 ]; then
        elevated_exec delete_netns ns0
        return 1
    fi

    elevated_exec create_veth_pair "ns0v1" "ns0v2" || OvsTestAssertFailure "unable to create veths for ns0"
    if [ $? == 1 ]; then
        elevated_exec delete_netns ns0
        elevated_exec delete_netns ns1
        return 1
    fi
    elevated_exec ip link set ns0v2 up
    elevated_exec ip link set ns0v1 netns ns0
    elevated_exec with_namespace ns0 ip link set ns0v1 up
    elevated_exec with_namespace ns0 ip addr add 172.31.110.1/24 dev ns0v1

    create_veth_pair "ns1v1" "ns1v2" || OvsTestAssertFailure "unable to create veths for ns1"
    if [ $? == 1 ]; then
        elevated_exec delete_netns ns0
        elevated_exec delete_netns ns1
        elevated_exec destroy_veth_pair ns0v1
        return 1
    fi
    elevated_exec ip link set ns1v1 up
    elevated_exec ip link set ns1v2 up
    elevated_exec ip link set ns1v1 netns ns1
    elevated_exec with_namespace ns1 ip link set ns1v1 up
    elevated_exec with_namespace ns1 ip addr add 172.31.110.2/24 dev ns1v1

    elevated_exec ${OVS_PREFIX}/bin/ovs-vsctl add-port tbr0 ns0v2
    elevated_exec ${OVS_PREFIX}/bin/ovs-vsctl add-port tbr0 ns1v2

    elevated_exec with_namespace ns1 ping -c1 172.31.110.1
    if [ $? -ne 0 ]; then
        OvsTestAssertFailure "Bad ping - $?"
        with_namespace ns1 ip addr
        with_namespace ns0 ip addr
    else
        testAssertPass
    fi
    destroy_veth_pair ns0v1
    destroy_veth_pair ns1v1
    delete_netns ns0
    delete_netns ns1
    stop_openvswitch

    return 0
}

test_openvswitch_dpdk_vhostuser() {
    VM_ONE=$(get_config "ovs_vm1")
    VM_TWO=$(get_config "ovs_vm2")

    if [ ! "$VM_ONE" -o ! "$VM_TWO" ]; then
        if [ ! "$VM_ONE" ]; then
            VM_ONE="fed28_1"
            if ! make_vhost_vm "$VM_ONE" "Fedora" "28" "x86_64" "root" "http://mirrors.oit.uci.edu/fedora/linux/releases/28/Server/x86_64/iso/Fedora-Server-dvd-x86_64-28-1.1.iso" "br0"; then
                log_err "Bad VM - set ovs_vm1 in your configuration"
                testAssertSkip "Skipping vhostuser test"
            fi
            return 1
        fi

        if [ ! "$VM_TWO" ]; then
            VM_TWO="fed28_2"
            if ! make_vhost_vm "$VM_TWO" "Fedora" "28" "x86_64" "root" "http://mirrors.oit.uci.edu/fedora/linux/releases/28/Server/x86_64/iso/Fedora-Server-dvd-x86_64-28-1.1.iso" "br0"; then
                log_err "Bad VM - set ovs_vm2 in your configuration"
                testAssertSkip "Skipping vhostuser test"
                return 1
            fi
        fi
    fi

    if ! start_openvswitch; then
        testAssertFailure "Unable to start OVS"
        return 1
    fi

    elevated_exec timeout 120 virsh start $VM_ONE
    elevated_exec timeout 120 virsh start $VM_TWO

    sleep 120

    RUNNING1=$(elevated_exec virsh list | grep $VM_ONE | awk '{ print $3; }')
    RUNNING2=$(elevated_exec virsh list | grep $VM_ONE | awk '{ print $3; }')

    if [ "$RUNNING1" != "running" -o "$RUNNING2" != "running" ]; then
        elevated_exec virsh destroy $VM_ONE
        elevated_exec virsh destroy $VM_TWO
        OvsTestAssertFailure "unable to start vms"
        return 1
    fi
    testAssertPass
    elevated_exec virsh destroy $VM_ONE
    elevated_exec virsh destroy $VM_TWO
    stop_openvswitch
}


test_openvswitch_userspace_conntrack_xons_per_sec() {
    start_openvswitch || OvsTestAssertFailure "Unable to start ovs"
    if [ $? == 1 ]; then
        return 1
    fi

    ovs_vsctl set Open_vSwitch . other_config:dpdk-init="true" || \
        OvsTestAssertFailure "Unable to start dpdk"
    if [ $? == 1 ]; then
        return 1
    fi

    sleep 15

    make_netns ns0
    make_netns ns1
    attach_veth_ovs_bridge "tbr0" "ns1" "v0"
    if [ $? == 1 ]; then
        return 1
    fi

    ovs_vsctl add-port "tbr0" "vhu0" -- set Interface "vhu0" \
              options:vhost-server-path="/tmp/vhu0" || \
        OvsTestAssertFailure "Unable to create vhu0"
    if [ $? == 1 ]; then
        return 1
    fi
    
    (echo start && tail -f /dev/null) | \
        testpmd --socket-mem=512 \
                --vdev="net_virtio_user,path=/tmp/vhu0,server=1" \
                --vdev="net_tap0,iface=tap0" \
                --file-prefix page0 \
                --single-file-segments -- \
                -a >/tmp/testpmd-vhu0.log 2>&1 &

    sleep 2

    elevated_exec ip link set tap0 netns ns0
    elevated_exec ip netns exec ns0 ip link set tap0 up
    elevated_exec ip netns exec ns0 ip addr add 172.31.110.1/24 dev tap0

    elevated_exec ip netns exec ns1 ip link set v0 up
    elevated_exec ip netns exec ns1 ip addr add 172.31.110.2/24 dev v0

    elevated_exec ip netns exec ns1 ping -c 4 172.31.110.1

    testAssertPass
    pkill -f -x -9 'tail -f /dev/null'
    stop_openvswitch
    return 0
}

TESTID=0
RUNTIME=$(date -Iminutes)
export MASTER_LOG_FILE=openvswitch-${RUNTIME}.log
for TEST in $(egrep ^test_ $0 | egrep '[({]' | sed 's@[{()}]*@@g'); do
    if [ "$1" = "list" ]; then
        echo $TEST
        continue
    fi
    log_debug "Running $TEST"
    TESTID=$((TESTID+1))
    if [ "X$1" != "X" ]; then
        if [ "$1" != "$TEST" ]; then
            testAssertSkip "skipping $TEST" "$TEST"
        else
            $TEST
        fi
    else
        $TEST
    fi
done

if [ "$1" != "list" ]; then
    report | tee openvswitch-${RUNTIME}.xml
fi
