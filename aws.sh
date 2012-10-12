#!/bin/sh

erl -pa ebin -pa deps/*/ebin -s dps_aws -name dps@`hostname -i`
