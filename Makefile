HUB_IP:=10.0.1.0

all:
	./jim.pl ls|xargs -n1 basename| xargs -n1 ./jim.pl

test:
	@test -f jim.json && (echo "You have jim.json already, move it away" && exit 1) || echo "We'll create a new jim.json DB"
	./jim.pl --create
	./jim.pl add top
	./jim.pl set top owner '["tzz"]'
	./jim.pl set-context top global-class
	./jim.pl add hub top
	./jim.pl set hub '=+owner' '["jh"]'
	./jim.pl set-context hub hub-class
	./jim.pl add client top
	./jim.pl set client '=+owner' '["mark"]'
	./jim.pl set-context client client-class

ec2:
	@test -f jim.json && (echo "You have jim.json already, move it away" && exit 1) || echo "We'll create a new jim.json DB"
	./jim.pl --create
	./jim.pl add top-node
	./jim.pl ec2 bootstrap top-node 'myEC2key'

	./jim.pl add client top-node
	./jim.pl set client instances 10
	./jim.pl set client hub '"$(HUB_IP)"'
	./jim.pl set client ip '"auto"'
	./jim.pl set-context client cfclient
	./jim.pl set client type '"m1.small"'

	./jim.pl add hub top-node
	./jim.pl set hub instances 1
	./jim.pl set hub ip '"$(HUB_IP)"'
	./jim.pl set-context hub cfhub
	./jim.pl set hub type '"m1.medium"'

	@echo starting 1 hub instance
	./jim.pl ec2 start 1 hub
	@echo list all the instances
	./jim.pl ec2 list
	@echo starting all necessary instances
	./jim.pl ec2 start
	@echo list all the hub instances
	./jim.pl ec2 list hub
	@echo stopping 1 running client instance
	./jim.pl ec2 stop 1 client
	@echo stopping all running instances
	./jim.pl ec2 stop
	@echo list all the client instances
	./jim.pl ec2 list client
