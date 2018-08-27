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

__iptables_exists_fn() {
    type "$1" 2>&1 | grep -q 'function' 2>/dev/null
}


if ! __iptables_exists_fn 'with_temp_area'; then
    source ${SOURCE_LOCATION}core.sh
fi

iptables_temp_test_rule_success() {
    check_iptables_rule $@
    RESULT=$?
    if ! testAssertEQ $RESULT 1 "CHECK RULE"; then
        return 1
    fi
    add_iptables_rule_unique $@
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "ADD RULE"; then
        return 1
    fi
    check_iptables_rule $@
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "CHECK ADDED"; then
        return 1
    fi
    delete_iptables_rule $@
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "DELETE RULE"; then
        return 1
    fi
    return 0
}

test_successes() {
    TEST_ADD_SUCCESSES=("-p udp -m udp --sport 1" "-p udp -m udp --sport 65535" "-p udp -m udp --dport 1" "-p udp -m udp --dport 65535" "-p udp -m udp --sport 1:1023" "-p udp -m udp --sport 1024:65535" "-p udp -m udp ! --sport 1" "-p udp -m udp ! --sport 65535" "-p udp -m udp ! --dport 1" "-p udp -m udp ! --dport 65535" "-p udp -m udp --sport 1 --dport 65535" "-p udp -m udp --sport 65535 --dport 1" "-p udp -m udp ! --sport 1 --dport 65535" "-p udp -m udp ! --sport 65535 --dport 1")

    for TABLE in INPUT OUTPUT FORWARD; do
        for test_add in ${!TEST_ADD_SUCCESSES[@]}; do
            TESTID=$((TESTID+1))
            TEST_DATA=${TEST_ADD_SUCCESSES[$test_add]}
            log_info "Starting test $TESTID - $TABLE $TEST_DATA"
            if iptables_temp_test_rule_success $TABLE $TEST_DATA; then
                testAssertPass
            fi
        done
    done
}

test_block_port() {
    PORT_NO=2048
    random_number PORT_NO 2048

    insert_iptables_rule_unique INPUT -p tcp --dport $PORT_NO -j REJECT \
                             --reject-with tcp-reset
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "ADD TCP REJECT RULE"; then
        return 1
    fi

    add_iptables_rule_unique INPUT -p udp --dport $PORT_NO -j DROP
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "ADD UDP DROP RULE"; then
        return 1
    fi

    spawn_async_subshell run_listener $PORT_NO --send-only
    run_connect_and_quit 127.0.0.1 $PORT_NO --send-only
    RESULT=$?
    if ! testAssertEQ $RESULT 1 "FIRST CONNECT CHECK"; then
        return 1
    fi

    delete_iptables_rule INPUT -p tcp --dport $PORT_NO -j REJECT \
                         --reject-with tcp-reset
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "Dropping iptables rule"; then
        return 1
    fi

    ## NOTE: After this, if it is successful, the listener will be dead
    run_connect_and_quit 127.0.0.1 $PORT_NO --send-only
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "SECOND CONNECT CHECK"; then
        return 1
    fi

    delete_iptables_rule INPUT -p udp --dport $PORT_NO -j DROP
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "DEL UDP DROP RULE"; then
        return 1
    fi

    insert_iptables_rule_unique INPUT -p tcp --dport $PORT_NO -j DROP
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "ADD TCP DROP RULE"; then
        return 1
    fi

    spawn_async_subshell run_listener $PORT_NO --send-only
    run_connect_and_quit 127.0.0.1 $PORT_NO --send-only
    RESULT=$?
    if ! testAssertEQ $RESULT 1 "THIRD CONNECT CHECK"; then
        return 1
    fi

    delete_iptables_rule INPUT -p tcp --dport $PORT_NO -j DROP
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "KILL TCP DROP RULE"; then
        return 1
    fi

    run_connect_and_quit 127.0.0.1 $PORT_NO --send-only
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "THIRD CONNECT CHECK"; then
        return 1
    fi

    testAssertPass
    return 0
}


test_nfqueue() {
    PORT_NO=2048
    random_number PORT_NO 2048

    if ! elevated_exec pip install NetfilterQueue; then
        testAssertFailure "FAILURE - need NetfilterQueue installed"
        return 1
    fi

    PYFILE=""
    write_binary_temp_file PYFILE <<<00

    cat >$PYFILE <<EOF
from netfilterqueue import NetfilterQueue

numpkts = 2
def print_and_accept(pkt):
    global numpkts
    print pkt
    if numpkts == 0:
        pkt.accept()
    elif numpkts > 0:
        numpkts -= 1
        pkt.drop()

nfqueue = NetfilterQueue()
nfqueue.bind(1, print_and_accept)
try:
    nfqueue.run()
except KeyboardInterrupt:
    print

EOF

    if [ ! -e $PYFILE ]; then
        testAssertFailure Missing $PYFILE
        return 1
    fi

    insert_iptables_rule_unique INPUT -p tcp --dport $PORT_NO  -j NFQUEUE --queue-num 1
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "Insert Queue rule"; then
        rm $PYFILE
        return 1
    fi

    log_info Running python file $PYFILE

    spawn_async_subshell elevated_exec timeout -s SEGV 5m python $PYFILE
    spawn_async_subshell run_listener $PORT_NO --send-only

    # Give time for the processes to start
    sleep 10

    run_connect_and_quit 127.0.0.1 $PORT_NO --send-only
    RESULT=$?
    if ! testAssertEQ $RESULT 1 "First connect attempt"; then
        rm $PYFILE
        return 1
    fi

    run_connect_and_quit 127.0.0.1 $PORT_NO --send-only
    RESULT=$?
    if ! testAssertEQ $RESULT 1 "Second connect attempt"; then
        rm $PYFILE
        return 1
    fi

    run_connect_and_quit 127.0.0.1 $PORT_NO --send-only
    RESULT=$?
    if ! testAssertEQ $RESULT 0 "Third connect attempt"; then
        rm $PYFILE
        return 1
    fi

    rm $PYFILE
}

TESTID=0
RUNTIME=$(date -Iminutes)
export MASTER_LOG_FILE=iptables-${RUNTIME}.log
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
