all:
	./rebar compile

full:
	./rebar get-deps compile

clean:
	./rebar clean

.PHONY: test

test:
	./rebar eunit skip_deps=true

1:
	erl -pa ebin -pa deps/*/ebin -s dps_example -sname node1

2:
	erl -pa ebin -pa deps/*/ebin -s dps_example -sname node2

3:
	erl -pa ebin -pa deps/*/ebin -s dps_example -sname node3

4:
	erl -pa ebin -pa deps/*/ebin -s dps_example -sname node4


bench:
	./rebar compile skip_deps=true
	erl -pa ebin -pa deps/*/ebin -smp enable -s dps_benchmark run1 -sname bench@localhost -setcookie cookie

PLT_NAME=.dps.plt

$(PLT_NAME):
	@ERL_LIBS=deps dialyzer --build_plt --output_plt $@ \
		--apps kernel stdlib crypto || true

dialyze: $(PLT_NAME)
	@dialyzer ebin --plt $(PLT_NAME) --no_native \
		-Werror_handling -Wunderspecs

