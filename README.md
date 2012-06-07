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
    jim set a b '{ c: "d" }'
    jim set-context a b 1 or 0 or '"cfengine expression"'

Setting "$+varname" means you want to augment varname (only arrays and hashes).
Setting "$-varname" means you want to decrement varname (only arrays and hashes),

Add a node with parents a and b; node names are unique,

    jim add node1 a b
    jim rm node1

# TODO

Provide feedback hooks so jim can pick up node knowledge (and maybe
bubble common traits through the hierarchy--if everyone that inherits
from you has X, you get X)
