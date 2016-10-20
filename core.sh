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


PASSED=()
FAILED=()

report(){
    # xunit xml
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone='yes'?>"
    echo "<TestRun>"
    OLDIFS=$IFS; IFS=','
    if [ ${#FAILED[@]} -ne 0 ]; then
        echo "  <FailedTests>"
        for FAILURE in "${FAILED[@]}"; do
            set $FAILURE
            echo "    <FailedTest id=\"$2\"><Name>$1</Name><FailureType>Assertion</FailureType><Message>assertion failed - Expected $3 but got $4. $5</FailedTest>"
        done
        echo "  </FailedTests>"
    else
        echo "  <FailedTests/>"
    fi
    echo "  <SuccessfulTests>"
    for SUCCESS in "${PASSED[@]}"; do
        set $SUCCESS
        echo "    <Test id=\"$2\"><Name>$1</Name></Test>"
    done
    echo "  </SuccessfulTests>"
    echo "  <Statistics>"
    NUMTESTS=("${PASSED[@]}" "${FAILED[@]}")
    echo "     <Tests>${#NUMTESTS[@]}</Tests>"
    echo "     <FailuresTotal>${#FAILED[@]}</FailuresTotal>"
    echo "     <Errors>0</Errors>"
    echo "     <Failures>${#FAILED[@]}</Failures>"
    echo "  </Statistics>"

    echo "</TestRun>"
    IFS=$OLDIFS
}

log_debug() {
    echo "[`date`] DEBUG $@" | tee -a $MASTER_LOG_FILE $DEBUG_LOG_FILE
}

log_info() {
    echo "[`date`] INFO $@" | tee -a $MASTER_LOG_FILE $INFO_LOG_FILE
}

log_warn() {
    echo "[`date`] WARN $@" | tee -a $MASTER_LOG_FILE $WARNING_LOG_FILE
}

log_err() {
    echo "[`date`] ERROR $@" | tee -a $MASTER_LOG_FILE $ERROR_LOG_FILE
}

testAssertFailure(){
    FAILED=("${FAILED[@]}" "${FUNCNAME[1]},$TESTID,to pass,forced fail,$@")
    log_err "Failed $TESTID - ${FUNCNAME[1]} - $@"
    return 1
}

testAssertPass(){
    PASSED=("${PASSED[@]}" "${FUNCNAME[1]},$TESTID,pass,pass,$@")
    log_info "Passed $TESTID - ${FUNCNAME[1]} - $@"
    return 1
}

testAssertEQ(){
    EXPECTED=$1
    shift
    ACTUAL=$1
    shift
    if [ "$EXPECTED" == "$ACTUAL" ]; then
        log_info "Passed $TESTID - ${FUNCNAME[1]} - $@"
        return 0
    else
        FAILED=("${FAILED[@]}" "${FUNCNAME[1]},$TESTID,$EXPECTED,$ACTUAL,$@")
        log_err "Failed $TESTID - ${FUNCNAME[1]} - $@"
        return 1
    fi
}

testAssertNEQ(){
    EXPECTED=$1
    shift
    ACTUAL=$1
    shift
    if [ "$EXPECTED" != "$1" ]; then
        log_info "Passed $TESTID - ${FUNCNAME[1]} - $@"
        return 0
    else
        FAILED=("${FAILED[@]}" "${FUNCNAME[1]},$TESTID,$EXPECTED,$ACTUAL,$@")
        log_err "Failed $TESTID - ${FUNCNAME[1]} - $@"
        return 1
    fi
}

get_source_location() {
    SOURCE_LOCATION=$SCRIPT_LOCATION
    if [ "$SCRIPT_LOCATION" == "" ]; then
        SOURCE_LOCATION="./"
    fi
    eval "$1=$SOURCE_LOCATION"
}

elevated_exec() {
    log_debug Executing $@
    if [ "$USER" != "root" ]; then
        SOURCE_LOCATION=""
        get_source_location SOURCE_LOCATION
        sudo -s <<EOF
source ${SOURCE_LOCATION}core.sh
export MASTER_LOG_FILE=${MASTER_LOG_FILE}
$@
EOF
    else
        /bin/bash <<EOF
source ${SOURCE_LOCATION}core.sh
export MASTER_LOG_FILE=${MASTER_LOG_FILE}
$@
EOF
    fi
    return $?
}

try_install() {
    log_debug Attempting to install one of \[ "$@" \]
    if /usr/bin/rpm -q -f /usr/bin/rpm >/dev/null 2>&1; then
        log_debug "Detected RPM system"
        if which dnf >/dev/null 2>&1; then
            elevated_exec dnf install -y $2
        else
            elevated_exec yum install -y $2
        fi
    elif /usr/bin/dpkg --search /usr/bin/dpkg 2>&1; then
        log_debug "Detected DEB system"
        apt-get install -y $1
    fi
    return 0
}

get_bin(){
    BINARY=`which $2 2>/dev/null`
    if [ "$BINARY" == "" ]; then
        log_debug no binary
        if [ "$AUTO_INSTALL" == "yes" ]; then
            log_debug installing
            try_install $3 $4
            BINARY=`which $2 2>/dev/null`
            if [ "$BINARY" == "" ]; then
                log_debug failed installing binary
                return 1
            fi
        fi
    fi
    eval "$1=$BINARY"
    return 0
}

run_dig(){
    DIG_BIN=""
    if get_bin DIG_BIN dig dnsutils bind-utils; then
        $DIG_BIN $@ 
        return 0
    else
        return 1
    fi
}

run_ping() {
    RETURN=0
    log_debug ping requested for \[ "$@" \]
    PING_BIN=""
    if get_bin PING_BIN ping iputils-ping iputils; then
        for addr in $@; do
            $PING_BIN -c 1 $addr >/dev/null 2>&1 ||
                $PING_BIN -4 -c 1 $addr >/dev/null 2>&1 ||
                (log_err Failed to ping $addr; RETURN=1)
        done
    else
        log_err No ping binary found.
        RETURN=1
    fi
    return $RETURN
}

run_ssh() {
    RETURN=0
    log_debug ssh exec \[ "$@" \]
    SSH_BIN=""
    if get_bin SSH_BIN ssh openssh-client openssh-clients; then
        $SSH_BIN $@
        RETURN=$?
    else
        log_err No ssh binary found.
        RETURN=1
    fi
    return $RETURN
}

run_scp() {
    RETURN=0
    log_debug ssh exec \[ "$@" \]
    SCP_BIN=""

    if get_bin SCP_BIN scp openssh-client openssh-clients; then
        $SCP_BIN $@
        RETURN=$?
    else
        log_err No scp binary found.
        RETURN=1
    fi
    return $RETURN
}

log_output() {
    $@ | tee $MASTER_LOG_FILE
    RESULT=${PIPESTATUS[0]}
    log_debug "caught exit: $RESULT"
    return $RESULT
}

get_remote_ip() {
    REMOTE=$(echo $2 | rev | cut -d: -f2- | rev)
    eval "$1=$REMOTE"
    [ "$REMOTE" == "" ] || return 0
    return 1
}

get_remote_port() {
    REMOTE=""
    if grep -q ':' <<<$2; then
        REMOTE=$(echo $2 | cut -d: -f2)
        eval "$1=$REMOTE"
    fi
    [ "$REMOTE" == "" ] || return 0
    return 1
}

can_reach_internet() {
    NSARG=""
    if [ "$NETWORK_NAME_SERVER" != "" ]; then
        NSARG="@$NETWORK_NAME_SERVER"
    fi
    if run_dig $NSARG google.com >/dev/null 2>&1; then
        if run_ping google.com >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

spawn_async_subshell() {
    EXPORT_LOG=$MASTER_LOG_FILE
    NSENTER=""
    while [ "${1:0:2}" == "--" ]; do
        if [ "${1:2}" == "log-file" ]; then
            EXPORT_LOG=$2
            shift # need to shift off the extra arg
        elif [ "${1:2}" == "ip-ns" ]; then
            NSENTER="with_namespace $2"
            shift # need to shift off the extra arg
        fi
        shift
    done
    (MASTER_LOG_FILE=$EXPORT_LOG $NSENTER $@) &
    return $!
}

dotimes() {
    NUMTIMES=$1
    shift
    n=0
    while [[ $n -lt $NUMTIMES ]]; do
        $@
        n=$((n+1))
    done
}

with_remote_shell() {
    REMOTE_HOST=""
    REMOTE_PORT="22"
    get_remote_ip REMOTE_HOST $1
    get_remote_port REMOTE_PORT $1

    shift
    SOURCE_LOCATION=""
    get_source_location SOURCE_LOCATION
    SOURCE_FILE="${SOURCE_LOCATION}core.sh"

    log_info Writing /tmp/core.sh to remote host: $REMOTE_HOST
    run_scp -P $REMOTE_PORT $SOURCE_FILE $REMOTE_HOST:/tmp/core.sh
    log_output run_ssh -p $REMOTE_PORT $REMOTE_HOST "source /tmp/core.sh; $@"
    RESULT=$?
    log_info Removing /tmp/core.sh from remote host: $REMOTE_HOST
    run_ssh -p $REMOTE_PORT $REMOTE_HOST rm /tmp/core.sh
    return $RESULT
}

do_netns() {
    IPBIN=""
    OP=$1
    NETNS=$2
    RETURN=1
    shift
    shift
    if get_bin IPBIN ip iproute2 iproute; then
        log_info running $IPBIN netns $OP $NETNS $@
        elevated_exec $IPBIN netns $OP $NETNS $@
        RETURN=$?
        log_info elevated_exec ran $RETURN
    fi
    return $RETURN
}

make_temp_file() {
    FILE_MADE=$(mktemp)
    eval "$1=$FILE_MADE"
    return 0
}

iptables_rule() {
    IPTABLES_BIN=""
    if get_bin IPTABLES_BIN iptables iptables iptables; then
        log_info "IPT: [$@]"
        elevated_exec $IPTABLES_BIN $@
        return $?
    fi
    return 1
}

check_iptables_rule() {
    iptables_rule -C $@
    return $?
}

delete_iptables_rule() {
    iptables_rule -D $@
    return $?
}

add_iptables_rule() {
    iptables_rule -A $@
    return $?
}

add_iptables_rule_unique() {
    while check_iptables_rule $@ 2>/dev/null >/dev/null; do
        delete_iptables_rule $@
    done

    add_iptables_rule $@
    return $?
}

with_namespace() {
    SOURCE_LOCATION=""
    get_source_location SOURCE_LOCATION

    NETNS=$1
    shift
    make_temp_file FILENAME
    echo "source ${SOURCE_LOCATION}core.sh; set -x; $@ || exit 1" >$FILENAME
    chmod +x $FILENAME
    do_netns exec $NETNS $FILENAME
    cat $FILENAME
    rm $FILENAME
    return $?
}

make_netns() {
    NETNS=$1
    shift
    do_netns add $NETNS
}

delete_netns() {
    NETNS=$1
    shift
    do_netns delete $NETNS
}

random_string() {
    TMPNAME=$(mktemp -u)   # usually, unsafe
    _TMPNAME=$(basename $TMPNAME)
    RANDOM_STR=$(cut -d. -f2 <<<$_TMPNAME)
    if [ "$1" != "" ]; then
        eval "$1=$RANDOM_STR"
    fi
    echo $RANDOM_STR
    return 0
}

with_temp_namespace() {
    NAMESPACE=""
    random_string NAMESPACE >/dev/null 2>&1
    log_info Creating Temp Namespace: $NAMESPACE
    make_netns $NAMESPACE
    with_namespace $NAMESPACE $@
    RESULT=$?
    delete_netns $NAMESPACE
    return $RESULT
}

create_veth_pair() {
    if [ "$1" != "" ]; then
        PORT_A=$1
        shift
    fi

    if [ "$1" != "" ]; then
        PORT_B=$1
        shift
    fi

    if [ "$PORT_A" == "" ]; then
        return 1
    fi

    IPBIN=""
    if get_bin IPBIN ip iproute2 iproute; then
        PEER_NAME=""
        if [ "$PORT_B" != "" ]; then
            PEER_NAME="peer name $PORT_B"
        fi
        elevated_exec $IPBIN link add name $PORT_A type veth $PEER_NAME
    fi
    if [ $? ]; then
        if [ "$1" != "" ]; then
            elevated_exec $IPBIN link set netns $1
        fi
    fi
    return $?
}

destroy_veth_pair() {
    if [ "$1" != "" ]; then
        PORT_A=$1
        shift
    fi

    if [ "$PORT_A" == "" ]; then
        return 1
    fi

    IPBIN=""
    if get_bin IPBIN ip iproute2 iproute; then
        elevated_exec $IPBIN link delete dev $PORT_A type veth
    fi
    return $?
}

launch_iperf() {
    IPERFBIN=""

    if get_bin IPERFBIN iperf3 iperf3 iperf3; then
        $IPERFBIN $@ | tee -a $IPERF_LOG_FILE
    fi
    return $?
}

launch_iperf_server() {
    launch_iperf -s $@
    return $?
}

cd_and_run() {
    TMPDIR=$1
    shift

    pushd $TMPDIR >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        return 1
    fi

    if [ $# -eq 0 ]; then
        OLD_IFS=$IFS
        IFS=' '
        while read EXECLINE; do
            echo $EXECLINE
            ${EXECLINE[*]} # ${EXECLINE[1]} ${EXECLINE[2]} ${EXECLINE[3]}
            if [ $? -ne 0 ]; then
                RESULT=1
            fi
        done
        IFS=$OLD_IFS
    else
        $@
        RESULT=$?
    fi
    popd >/dev/null 2>&1

}
with_temp_area() {
    TMPDIR=$(mktemp -d)  # NOTE: this could be unsafe
    RESULT=0
    cd_and_run $TMPDIR $@
    rm -rf $TMPDIR
    return $RESULT
}

with_temp_git_clone () {
    GIT_BIN=""
    RESULT=1
    if get_bin GIT_BIN git git-core git-core; then
        URLNAME=$1
        shift
        git clone $URLNAME
        DIRNAME=$(basename $URLNAME .git)
        cd_and_run $DIRNAME $@
        RESULT=$?
        rm -rf $DIRNAME
    fi
    return $RESULT
}

write_binary_temp_file() {
    TMPFILE=$(mktemp)
    eval "$1=$TMPFILE"

    shift

    if [ $# -eq 0 ]; then
        IFS=' ' read -a BINARY_BYTES
    else
        BINARY_BYTES=($@)
    fi

    for BINARYBYTE in ${BINARY_BYTES[@]}; do
        echo -n -e \\x$BINARYBYTE >> $TMPFILE
    done
}

disassemble_stream() {
    ARCH=$1
    shift
    TEMP_FILENAME=""

    write_binary_temp_file TEMP_FILENAME $@
    objdump -D -b binary -m $ARCH $TEMP_FILENAME
    rm $TEMP_FILENAME
}

make_vm() {
    if [ -z ${FEDORA_WORKSTATION_VERSIONS+x} ]; then
        FEDORA_WORKSTATION_LATEST="24"
        FEDORA_WORKSTATION_VERSIONS=(23 24)
        FEDORA_WORKSTATION_IMAGES_x86_64=(http://ftp.uci.edu/fedora/linux/releases/23/Workstation/x86_64/iso/Fedora-Live-Workstation-x86_64-23-10.iso http://ftp.uci.edu/fedora/linux/releases/24/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-24-1.2.iso)
        FEDORA_WORKSTATION_IMAGES_i686=(http://ftp.uci.edu/fedora/linux/releases/23/Workstation/i386/iso/Fedora-Live-Workstation-i686-23-10.iso http://ftp.uci.edu/fedora/linux/releases/24/Workstation/i386/iso/Fedora-Workstation-Live-i386-24-1.2.iso)
        FEDORA_WORKSTATION_IMAGES_armhfp=()
    fi

    if [ -z ${FEDORA_SERVER_VERSIONS+x} ]; then
        FEDORA_SERVER_LATEST="24"
        FEDORA_SERVER_VERSIONS=(23 24)
        FEDORA_SERVER_IMAGES_x86_64=(http://ftp.uci.edu/fedora/linux/releases/23/Server/x86_64/iso/Fedora-Server-DVD-x86_64-23.iso http://ftp.uci.edu/fedora/linux/releases/24/Server/x86_64/iso/Fedora-Server-dvd-x86_64-24-1.2.iso)
        FEDORA_SERVER_IMAGES_i686=(http://ftp.uci.edu/fedora/linux/releases/23/Server/i386/iso/Fedora-Server-DVD-i386-23.iso http://ftp.uci.edu/fedora/linux/releases/24/Server/i386/iso/Fedora-Server-dvd-i386-24-1.2.iso)
    fi

    VMNAME=""
    VMOS=""
    VMOS_VER=""
    VMARCH="x86_64"
    VMKPARAM=""
    VMROOTPW=$(random_string)
    VMDISKSIZE="8G"

    while [ "$1" != "" ]; do
        if [ "${1:0:2}" == "--" ]; then
            case ${1:2} in
                vmname)
                    VMNAME="$2"
                    shift
                    ;;
                vmos)
                    VMOS=$2
                    shift
                    ;;
                vmver)
                    VMOS_VER=$2
                    shift
                    ;;
                arch|vmarch)
                    VMARCH=$2
                    shift
                    ;;
                kcmd)
                    VMKPARAM="$2"
                    shift
                    ;;
                password)
                    VMROOTPW="$2"
                    shift
                    ;;
                size)
                    VMDISKSIZE="$2"
                    shift
                    ;;
                *)
                    log_err Unknown Option $1
                    return 1
                    ;;
            esac
        else
            if [ "$VMNAME" == "" ]; then
                VMNAME="$1"
            elif [ "$VMOS" == "" ]; then
                VMOS=$1
            elif [ "$VMOS_VER" == "" ]; then
                VMOS_VER=$1
            fi
        fi
        shift
    done

    if [ "$VMOS_VER" == "" ]; then
        VMOS_VER="latest"
    fi

    if [ "$VMNAME" == "" -o "$VMOS" == "" ]; then
        log_err Unable to instantiated OS - need name, type, and version
        log_debug NAME: $VMNAME , OS: $VMOS , VER: $VMOS_VER
        return 1
    fi

    VERS=${VMOS^^}_VERSIONS
    eval LOAD_VERS_TYPE=\$$VERS
    if [ "$LOAD_VERS_TYPE" == "" ]; then
        log_err Unknown VMOS - ${VMOS}.  Set the ${VMOS^^}_VERSIONS variable
        log_debug VERS: $VERS
        return 1
    fi

    if [ "$VMOS_VER" == "latest" ]; then
        VERS_LATEST=${VMOS^^}_LATEST
        log_debug LATEST: \$$VERS_LATEST
        eval "VMOS_VER=\${$VERS_LATEST}"
    fi

    log_debug VERS: $VMOS_VER
}


#pid=`docker inspect -f '{{.State.Pid}}' $container_id`
#ln -s /proc/$pid/ns/net /var/run/netns/$container_id
