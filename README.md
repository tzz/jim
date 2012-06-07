jim
===

Jim (is an) Inventory Manager

# Data

JSON format for a node:

    { learned_vars: {}, vars: {}, learned_contexts: {}, contexts: {}, tags: {}, inherit: { "x": {}, "y": { augment: ["arrayZ"] } } }

# HOWTO

    jim --cfmodule node1
    jim --puppet node1
    jim --json node1
    jim search TERM1 [and|or TERM2] [and|or TERM3]
    jim ls [node]
    jim ls-json [node]
    # set/learn attribute b in node a (set == learn for the below, except tags)
    # all of these have unset/unlearn counterparts
    jim set a b '"c"'
    jim set a b '[ "c" ]'
    jim set a b '{ c: "d" }'
    jim set-context a b 1 or 0 or '"cfengine expression"'
    
    # add takes --augment PARAM and --decrement PARAM (-a and -d) to indicate that instead of override, we should add or subtract attributes
    
    # add a node with parents a and b; node names are unique
    jim add node1 a b
    jim rm node1

# TODO

Provide feedback hooks so jim can pick up node knowledge (and maybe
bubble common traits through the hierarchy--if everyone that inherits
from you has X, you get X)
