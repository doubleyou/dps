#!/bin/sh

erl -pa ebin -pa deps/*/ebin -s dps_aws -s dps -name dps@`hostname -i`
