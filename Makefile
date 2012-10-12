all: deps/cowboy/ebin/cowboy.beam
	./rebar compile skip_deps=true

deps/cowboy/ebin/cowboy.beam:
	./rebar get-deps compile

full:
	./rebar get-deps compile

clean:
	./rebar clean

.PHONY: test

test:
	./rebar eunit skip_deps=true

1:
	# ulimit -n 10240
	ERL_MAX_PORTS=10240 erl -pa ebin -pa deps/*/ebin -s dps_example -sname node1

2:
	# ulimit -n 10240
	ERL_MAX_PORTS=10240 erl -pa ebin -pa deps/*/ebin -s dps_example -sname node2

3:
	# ulimit -n 10240
	ERL_MAX_PORTS=10240 erl -pa ebin -pa deps/*/ebin -s dps_example -sname node3

4:
	# ulimit -n 10240
	ERL_MAX_PORTS=10240 erl -pa ebin -pa deps/*/ebin -s dps_example -sname node4

aws: all
	./aws.sh


bench:
	./rebar compile skip_deps=true
	ERL_MAX_PORTS=10240 erl -pa ebin -pa deps/*/ebin -smp enable -s dps_benchmark run1 -sname bench@localhost -setcookie cookie

PLT_NAME=.dps.plt

$(PLT_NAME):
	@ERL_LIBS=deps dialyzer --build_plt --output_plt $@ \
		--apps kernel stdlib crypto || true

dialyze: $(PLT_NAME)
	@dialyzer ebin --plt $(PLT_NAME) --no_native \
		-Werror_handling -Wunderspecs

