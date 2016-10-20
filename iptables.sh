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

TESTID=1

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
            TEST_DATA=${TEST_ADD_SUCCESSES[$test_add]}
            log_info "Starting test $TESTID - $TABLE $TEST_DATA"
            if iptables_temp_test_rule_success $TABLE $TEST_DATA; then
                testAssertPass
            fi
            TESTID=$((TESTID+1))
        done
    done
}

test_successes

report
