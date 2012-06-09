HUB_IP:=10.0.1.0

all:
	./jim.pl ls|xargs -n1 basename| xargs -n1 ./jim.pl

test:
	@test -f jim.json && (echo "You have jim.json already, move it away" && exit 1) || echo "We'll create a new jim.json DB"
	./jim.pl --create
	./jim.pl add top
	./jim.pl set top owner '["tzz"]'
	./jim.pl set-context top ec2 true
	./jim.pl add hub top
	./jim.pl set hub '=+owner' '["jh"]'
	./jim.pl set hub instances 1
	./jim.pl set hub ip '"$(HUB_IP)"'
	./jim.pl set-context hub cfhub true
	./jim.pl add client top
	./jim.pl set client '=+owner' '["mark"]'
	./jim.pl set client instances 10
	./jim.pl set client hub '"$(HUB_IP)"'
	./jim.pl set-context client cfclient true
