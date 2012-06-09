jim
===

Jim (is an) Inventory Manager

# Data

JSON format for a node:

    { learned_vars: {}, vars: {}, learned_contexts: {}, contexts: {}, tags: {}, inherit: { "x": {}, "y": { } } }

# HOWTO

    jim --cfmodule node1
    jim --puppet node1
    jim --json node1

Search is an implied OR using regular expressions.

    jim search TERM1 [ TERM2 TERM3]
    jim ls [node]
    jim ls-json [node]

This is how you set/learn attribute b in node a (set == learn for the below, except tags).
All of these have unset/unlearn counterparts.

    jim set a b '"c"'
    jim set a b '[ "c" ]'
    jim set a b '{ "c": "d" }'
    jim set-context a b 1 or 0 or true or false or '"cfengine expression"'

You can omit the value for context.  It's assumed to be true in that case.

Setting "=+varname" means you want to augment varname (only arrays and hashes).
Setting "=-varname" means you want to decrement varname (only arrays and hashes),

Putting "$(varname)" in a value expands it to the value of that
attribute, and causes a fatal error if varname is missing.  Do it only
for set/learned values, it won't work for contexts.

    jim set a interpolated '"$(x)"'

Add a node with parents a and b; node names are unique.

    jim add node1 a b
    jim rm node1

Change the parents to a new list.

    jim parents node1 b

# Plugins

## EC2 plugin

Create the necessary entries in a node, which you can inherit.

    jim ec2 bootstrap top-node 'myEC2key'

Add a client node inheriting from the top-node template and with 10 instances

    jim add client top-node
    jim set client instances 10
	jim set client hub '"10.0.11.12"'
    jim set client ip '"auto"'
    jim set-context client cfclient

Initialize a hub node to use the top-node template and have 1 instances

    jim add hub top-node
    jim set hub instances 10
    jim set hub ip '"10.0.11.12"'
    jim set-context hub cfhub

# Rules

Rules are not only TODO, but very hazardous to your mental health.

TODO: Add a rule to set subnet to 192.168.2/24 when 'colo' is 'CHI'.

    jim add-rule chi-colo-subnet '(when (equal (get this "colo") "CHI") (set this "subnet" "192.168.2/24"))'

TODO: Add a rule to add 'tzz' to 'sudoers' when 'tags' contains 'devbox'.

    jim add-rule devbox-tzz-sudoers '(when (member (get this "tags") "devbox") (push this "sudoers" "tzz"))'

TODO: Add a rule to set 'has_owner' to 'yes'/'no' when 'owner' is present/missing.

    jim add-rule set-has-owner '(set this "has_owner" (if (has this "owner") "yes" "no"))'

Remove a rule by name:

    jim rm-rule set-has-owner

# TODO

Provide feedback hooks so jim can pick up node knowledge (and maybe
bubble common traits through the hierarchy--if everyone that inherits
from you has X, you get X)
