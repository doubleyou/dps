all:
	./rebar compile

full:
	./rebar get-deps compile

clean:
	./rebar clean

test: all
	./rebar eunit skip_deps=true

1:
	erl -pa ebin -s dps -sname node1

2:
	erl -pa ebin -s dps -sname node2

3:
	erl -pa ebin -s dps -sname node3

4:
	erl -pa ebin -s dps -sname node4
