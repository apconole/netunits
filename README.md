Network Unit / Integration Tests
================================

## Contents

- [General](#general)
- [Writing Tests](#coding)
- [IPTables Suite](#iptables)
- [Licensing](#licensing)

## General

### What is this?

The network unit / integration tests aim to be a flexible set of bash scripts
and functions used to write unit and integration tests for various normal and
edge cases in userspace - networking testing.  One of the primary goals is to
catch regressions in linux kernel changes.

### Why yet-another suite?

I like using bash to do these tests, and it turns out a lot of existing scripts 
are already existing in bash, so porting them should be a simple task.

### Okay, how do I use it?

Each test-suite will be it's own .sh file, which will use the special variable
`SOURCE_LOCATION` to find **core.sh**, which has most of the functionality.
Simply make sure `SOURCE_LOCATION` is set to this git directory and you should
be able to run the executables.

When the executable is finished, it will spit out an xml report.  This is in the
xUnit format, so it is suitable for consumption by any tool which reads xUnit xml.

## Coding

### Writing a test

There are a few functions built in for setting up the report.  Typically, you will
create a condition, test that condition, and then write a report on the results.
Finally, the report can be written by running the `report` function.

Let's code an example suite, called the simple suite.  Paste the code below into a
new file, called **simple.sh**

```shell
#!/bin/bash
__simple_exists_fn() {
    type "$1" 2>&1 | grep -q 'function' 2>/dev/null
}


if ! __simple_exists_fn 'report'; then
    source ${SOURCE_LOCATION}core.sh
fi

test_something_simple() {
    TESTID=1
    if ! testAssertEQ 1 1 "This test is equal"; then
       return 1
    fi
    testAssertPass
    return 0
}

a_more_complex_test() {
    TESTID=2
    with_temp_area /bin/ls
    RESULT=$?
    if ! testAssertEQ 0 $RESULT "Temp area list"; then
        return 1
    fi

    with_temp_area /sbin/ls
    RESULT=$?
    if ! testAssertNEQ 0 $RESULT "Temp area failed list"; then
        return 1
    fi
    testAssertPass "Temp area Lists"
    return 0
}

test_something_simple
a_more_complex_test

report
```

Making this file executable and running it should present an XML suite which
demonstrates pass and fail XML reports.

Note the special variable `TESTID`, which will be used as the test index.

### Special functions available

#### Logging

All logging is configured to print both to stdout, and the `MASTER_LOG_FILE`.  The
following logging functions exist:

* log_debug ...
  Make a debug log.

* log_info ...
  Make an info-level log.

* log_warn ...
  Make a warning-level log.

* log_err ...
  Man an error-level log.


#### Testing for conditions

The following will log a pass or failure in the test logs.  It's important to abort
the currently running test once it has been added to a list.

* testAssertPass
  The only way to get a PASS entry in the final report
  
* testAssertFailure
  Adds the current test to the FAIL entries

* testAssertEQ ACTUAL EXPECTED [TEXT]
  If the values are equal, log and return 0.  Otherwise, add the test to the failure
  case, log, and return 1.
  
* testAssertNEQ ACTUAL EXPECTED [TEXT]
  Same as previous, only for values which are not equal.


#### Extra helpers

* elevated_exec ...
  Runs `sudo` before executing the specified commands.
  
* try_install DEBIAN-PKG REDHAT-PKG
  Tries to install the package specified.  Uses `apt-get install -y DEBIAN-PKG` for
  Debian based systems (ubuntu, debian), and either `yum` or `dnf` for Red Hat based
  systems.

* get_bin BINARY_VARIABLE binary DEBIAN-PKG REDHAT-PKG
  Tries to get the location of `binary`.  If `binary` is not found in the PATH, tries
  to install the associated package, and then re-try the search.  If `binary` is 
  found in the path, set the contents of BINARY_VARIABLE to the full path.

* log_output ...
  Logs the output of the command(s).

* spawn_async_subshell ...
  Spawns a sub-shell in the background and continues execution in parallel.

* random_string
  Generates a random string.


#### Network Helpers
  
* run_dig ARGS
  Runs `dig` and logs the results

* run_ping HOSTS
  Runs `ping` for each host, once, and logs the results.

* run_ssh ARGS ...
  Runs `ssh` against a host, and executes the commands passed.

* run_scp ARGS ...
  Copies files to a remote host

* can_reach_internet
  Returns whether the internet is reachable.


#### With- constructs

The following functions are considered _with-constructs_.  A _with-construct_ 
generally switches to some temporary or permanent resource before continuing.

* with_remote_shell HOST[:PORT] ...
  Connects via ssh to the remote host specified by HOST[:PORT] and executes the
  commands provided.
  
* with_namespace NAMESPACE ...
  Switches to the namespace specified by NAMESPACE and executes the commands 
  provided.
  
* with_temp_namespace ...
  Creates a temporary namespace and executes the commands provided
  
* with_temp_area ...
  Creates a temporary directory and executes the commands provided
  
* with_temp_git_clone GITURL
  Runs a `git clone` on the GITURL, executes the commands provided, and then 
  deletes the git directory.
  

## iptables

The **iptables** suite is located in the **iptables.sh** file.  It adds, deletes,
and exercises rules.


## Licensing

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with this program.  If not, see <http://www.gnu.org/licenses/>.
