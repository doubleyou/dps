all:
	./rebar compile

clean:
	./rebar clean

test:
	./rebar eunit

1:
	erl -pa ebin -s dps -sname node1

2:
	erl -pa ebin -s dps -sname node2

3:
	erl -pa ebin -s dps -sname node3

4:
	erl -pa ebin -s dps -sname node4
