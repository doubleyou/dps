all:
	./rebar compile

clean:
	./rebar clean

test:
	./rebar eunit skip_deps=true

1:
	erl -pa ebin -s dps -sname node1

2:
	erl -pa ebin -s dps -sname node2

3:
	erl -pa ebin -s dps -sname node3

4:
	erl -pa ebin -s dps -sname node4


PLT_NAME=.dps.plt

$(PLT_NAME):
	@ERL_LIBS=deps dialyzer --build_plt --output_plt $@ \
		--apps kernel stdlib crypto || true

dialyze: $(PLT_NAME)
	@dialyzer ebin --plt $(PLT_NAME) --no_native \
		-Werror_handling -Wunderspecs

