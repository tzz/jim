all:
	./jim.pl ls|xargs -n1 basename| xargs -n1 ./jim.pl
