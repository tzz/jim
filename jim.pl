#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;
use File::Basename;
use Getopt::Long;

my $coder;
my $canonical_coder;

BEGIN
{
    eval
    {
     require JSON::XS;
     $coder = JSON::XS->new()->relaxed()->utf8()->allow_nonref();
     # for storing JSON data so it's directly comparable
     $canonical_coder = JSON::XS->new()->canonical()->utf8()->allow_nonref();
    };
    if ($@ )
    {
     warn "Falling back to plain JSON module (you should install JSON::XS)";
     require JSON;
     $coder = JSON->new()->relaxed()->utf8()->allow_nonref();
     # for storing JSON data so it's directly comparable
     $canonical_coder = JSON->new()->canonical()->utf8()->allow_nonref();
    }
}

$| = 1;                         # autoflush

my %options =
 (
  verbose    => 0,
  quiet      => 0,
  help       => 0,
  create     => 0,
  cfmodule   => 0,
  yaml       => 0,
  json       => 0,
  plugins    => 1,

  database   => "jim.json"
 );

my @options_spec =
 (
  "quiet|q!",
  "help!",
  "verbose|v!",
  "plugins|p!",
  "cfmodule|cf!",
  "yaml|y!",
  "json|j!",
  'augment|a=s@',
  'decrement|d=s@',
  "create!",
  "database|db=s"
 );

GetOptions (
            \%options,
            @options_spec,
           );

if ($options{help})
{
 print <DATA>;
 exit;
}

my $verbose = $options{verbose};
my $quiet   = $options{quiet};

if ($options{create})
{
 write_jim_db($options{database});
 exit;
}

my @modified;
my @data_containers = qw/learned_vars vars/;
my @context_containers = qw/learned_contexts contexts/;
my @containers = (@data_containers, @context_containers);

my %handlers = (
                rules => sub
                {
                 my $db = shift @_;
                 foreach my $name (sort keys %{$db->{rules}})
                 {
                  printf "%s\t%s\n", $name, $db->{rules}->{$name};
                 }
                },

                ls => sub
                {
                 my $db = shift @_;
                 my @search = @_;
                 @search = keys %{$db->{nodes}} unless scalar @search;

                 my @results = ls($db, \@search, sub
                                 {
                                  print dirname_inherited($db, shift), "\n";
                                 });

                 exit !scalar @results;
                },

                'ls-json' => sub
                {
                 my $db = shift @_;
                 my @search = @_;
                 @search = keys %{$db->{nodes}} unless scalar @search;

                 my @results = ls($db, \@search, sub
                                 {
                                  printf("%s\t%s\n",
                                         dirname_inherited($db, shift),
                                         $coder->encode(shift));
                                 });

                 exit !scalar @results;
                },

                search => sub
                {
                 my $db = shift @_;
                 my @search = @_;

                 @search = '.' unless scalar @search;

                 my @results = search($db, \@search);

                 print join(' ',
                            sort map
                            {
                             dirname_inherited($db, $_->{name})
                            } @results), "\n";
                 exit !scalar @results;
                },

                set => sub
                {
                 general_set('set', @_);
                },

                learn => sub
                {
                 general_set('learn', @_);
                },

                'set-context' => sub
                {
                 general_set('set-context', @_);
                },

                'learn-context' => sub
                {
                 general_set('learn-context', @_);
                },

                unset => sub
                {
                 general_unset('unset', @_);
                },

                unlearn => sub
                {
                 general_unset('unlearn', @_);
                },

                'unset-context' => sub
                {
                 general_unset('unset-context', @_);
                },

                'unlearn-context' => sub
                {
                 general_unset('unlearn-context', @_);
                },

                add => sub
                {
                 my $db = shift @_;
                 my $name = shift @_;
                 my @parents = @_;

                 ensure_node_valid($db, $name);

                 die "Node name $name already exists so 'add' must fail, sorry"
                  if exists $db->{nodes}->{$name};

                 foreach my $parent (@parents)
                 {
                  die "Node name $name wants parent $parent but we can't find it, sorry"
                  unless exists $db->{nodes}->{$parent};
                 }

                 $db->{nodes}->{$name} = {
                                          learned_vars => {},
                                          vars => {},
                                          learned_contexts => {},
                                          contexts => {},
                                          inherit => { map { $_ => {} } @parents }
                                         };
                 push @modified, $name;
                 print "DONE: add $name @parents\n"
                  unless $quiet;
                },

                parents => sub
                {
                 my $db = shift @_;
                 my $name = shift @_;
                 my @parents = @_;

                 ensure_node_exists($db, $name);

                 foreach my $parent (@parents)
                 {
                  die "Node name $name wants parent $parent but we can't find it, sorry"
                  unless exists $db->{nodes}->{$parent};
                 }

                 $db->{nodes}->{$name}->{inherit} = {map { $_ => {} } @parents};

                 push @modified, $name;
                 print "DONE: parents $name @parents\n"
                  unless $quiet;
                },

                rm => sub
                {
                 my $db = shift @_;
                 my @todo = @_;

                 die "Nothing given to remove" unless scalar @todo;

                 foreach my $name (@todo)
                 {
                  die "Node name $name does not exist so 'rm' must fail, sorry"
                   unless exists $db->{nodes}->{$name};

                  delete $db->{nodes}->{$name};
                  push @modified, $name;

                  validate_db($db);

                 print "DONE: rm $name\n"
                  unless $quiet;
                 }
                },

                'add-rule' => sub
                {
                 my $db   = shift @_;
                 my $name = shift @_;
                 my $rule = shift @_;

                 die "Invalid add-rule syntax, please see --help"
                  unless defined $rule;

                 die "Rule $name already exists so 'add-rule' must fail, sorry"
                  if exists $db->{rules}->{$name};

                 warn "TODO: add-rule";
                 ensure_rule_valid($db, $name);
                 $db->{rules}->{$name} = $rule;
                 push @modified, $name;
                },

                'rm-rule' => sub
                {
                 my $db    = shift @_;
                 my @todo = @_;

                 foreach my $name (@todo)
                 {
                  die "Rule $name does not exist so 'rm-rule' must fail, sorry"
                   unless exists $db->{rules}->{$name};
                  delete $db->{rules}->{$name};
                  push @modified, $name;
                 }
                },
               );

my %output_handlers = (
                       cfmodule => sub
                       {
                        my $db = shift @_;
                        my $name = shift @_;

                        ensure_node_exists($db, $name);
                        my $data = resolve_contents($db, $name);
                        my @parents_slist = recurse_print([ sort keys %{$db->{nodes}->{$name}->{inherit}} ],
                                                          "",
                                                          1);
                        print "+__jim\n";
                        print "=__jim_name=$name\n";
                        printf "\@__jim_parents=%s\n", $parents_slist[0]->{value};

                        foreach my $context_topk (qw/contexts learned_contexts/)
                        {
                         my %chash = %{$data->{$context_topk}};
                         my $prefix = ($context_topk eq 'contexts') ? '' : 'learned_';

                         foreach my $key (sort keys %chash)
                         {
                          my $pk = $key;
                          $pk =~ s/\W/_/g;
                          my $v = $chash{$key};
                          if (ref $v) # a boolean
                          {
                           print "+${prefix}$pk\n" if $v;
                          }
                          else  # a string or number
                          {
                           print "=${prefix}bycontext[$key]=$v\n";
                          }
                         }
                        }

                        foreach my $var_topk (qw/vars learned_vars/)
                        {
                         my %vhash = %{$data->{$var_topk}};
                         my $prefix = ($var_topk eq 'vars') ? '' : 'learned_';

                         foreach my $k (sort keys %vhash)
                         {
                          my $pk = $k;
                          $pk =~ s/\W/_/g;
                          foreach my $p (recurse_print($vhash{$k},
                                                       "${prefix}$pk",
                                                       1))
                          {
                           my $at = $p->{type} eq 'slist' ? '@' : '=';
                           my $v = $p->{value};
                           print "${at}$p->{path}=$v\n"
                          }
                         }
                        }
                       },

                       json => sub
                       {
                        my $db = shift @_;
                        my $name = shift @_;

                        ensure_node_exists($db, $name);
                        my $data = resolve_contents($db, $name);
                        print $coder->encode($data), "\n";
                       },

                       yaml => sub
                       {
                        my $db = shift @_;
                        my $name = shift @_;
                        die "TODO: YAML output of $name";
                       },
                      );

if ($options{plugins})
{
 foreach my $p (glob(dirname($0) . "/plugins/*.jim.pl"))
 {
  if ($p =~ m,/(.+)\.jim\.pl,)
  {
   my $pname = $1;
   print "Loading plugin $pname from $p\n"
    if $verbose;

   my $do = do $p;
   if ($do)
   {
    $handlers{$pname} = $do;
   }
   else
   {
    warn "Plugin $pname failed to load from $p!\n";
   }
  }
 }
}

my $db = validate_db(read_jim_db());
my $old_json = $canonical_coder->encode($db);
command_handler($db, @ARGV);

write_jim_db($options{database}, $db)
 if $canonical_coder->encode($db) ne $old_json;

exit 0;

# we may turn this into a parser eventually
sub command_handler
{
 my $db = shift @_;
 my @args = @_;

 # jim --cfmodule node1
 # jim --puppet node1
 # jim --json node1
 foreach my $output (qw/cfmodule yaml json/)
 {
  if ($options{$output})
  {
   die "Option --$output requires at least one argument, sorry."
    unless scalar @args;

   die "Only one parameter allowed after --$output but I got [@args], sorry."
    unless scalar @args == 1;
   $output_handlers{$output}->($db, $args[0]);

   return;
  }
 }

 die "Nothing to do, no arguments.  Try --help."
  unless scalar @args;

 my $verb = shift @args;

 foreach my $command (keys %handlers)
 {
  if ($verb eq $command)
  {
   $handlers{$command}->($db, @args);
   return;
  }
 }

 # jim node1
 if (exists $db->{nodes}->{$verb})
 {
  $output_handlers{cfmodule}->($db, $verb);
  return;
 }

 die "Sorry, I don't know what to do with [$verb @args] and it's not a node name.  Try --help.";
}

sub validate_db
{
 my $db = shift @_;

 unless ($db)
 {
  $db = read_jim_db();
 }

 die "Bad jim database: not a hash!"
  unless ref $db eq 'HASH';

 foreach (qw/metadata nodes/)
 {
  die "Bad jim database: no '$_' key!"
   unless exists $db->{$_};

  die "Bad jim database: '$_' value should be a hash!"
   unless ref $db->{$_} eq 'HASH';
 }

 my %nodes = %{$db->{nodes}};
 foreach my $node (sort keys %nodes)
 {
  my $v = $nodes{$node};
  # format:  { learned_vars: {}, vars: {}, learned_contexts: {}, contexts: {}, inherit: { "x": {}, "y": { } } }
  die "Node $node: record is not a hash" unless ref $v eq 'HASH';

  foreach (@containers, qw/inherit/)
  {
   die "Node $node: no '$_' key!"
    unless exists $v->{$_};

   die "Node $node: '$_' value should be a hash!"
    unless ref $v->{$_} eq 'HASH';
  }

  foreach my $parent (sort keys %{$v->{inherit}})
  {
   die "Node $node has invalid parent $parent!"
    unless exists $nodes{$parent};
  }
 }

 return $db;
}

sub ensure_rule_valid { return ensure_thing_valid('rule', @_); }
sub ensure_node_valid { return ensure_thing_valid('node', @_); }

sub ensure_thing_valid
{
 my $type = shift @_;
 my $db   = shift @_;
 my $name = shift @_;

 die "Non-empty $type name must be given, sorry"
  unless $name;
}

sub ensure_rule_exists { return ensure_thing_exists('rule', @_); }
sub ensure_node_exists { return ensure_thing_exists('node', @_); }

sub ensure_thing_exists
{
 my $type = shift @_;
 my $db   = shift @_;
 my $name = shift @_;

 die "$type $name doesn't exist, sorry"
  unless exists $db->{"${type}s"}->{$name};
}

sub ensure_kv_valid
{
 my $command = shift @_;
 my $key     = shift @_;
 my $value   = shift @_;

 ensure_k_valid($command, $key);

 die "No value provided for $command command, see --help"
  unless defined $value;
}

sub ensure_k_valid
{
 my $command = shift @_;
 my $key     = shift @_;

 die "No key provided for $command command, see --help"
  unless defined $key;
}

sub ensure_v_is_context
{
 my $command        = shift @_;
 my $original_value = shift @_;
 my $decoded_value  = shift @_;

 # we'll accept contexts like 123 without quotes, since we'll
 # stringify them later.  This may be a problem if a floating point
 # number gets downsampled, but it's still more convenient than
 # requiring every argument to be quoted.

 die "Value [$original_value] is not boolean or a string and $command command requires it, see --help"
  unless ((ref $decoded_value) eq '' ||
          is_json_boolean($decoded_value));
}

sub load_json
{
 my $f = shift @_;

 my $j;
 unless (open($j, '<', $f) && $j)
 {
  warn "Could not inspect $f: $!" unless $quiet;
  return;
 }

 return $coder->decode(join '', <$j>);
}

sub eval_any_json
{
 my $value = shift @_;

 my $wrap;
 eval
 {
  $wrap = $coder->decode(sprintf('{ "data": %s }', $value));
 };
 die "Could not evaluate value [$value] in a JSON context, sorry"
  unless (ref $wrap eq 'HASH' && exists $wrap->{data});

 return $wrap->{data};
}

sub general_set
{
 my $mode  = shift @_;
 my $db    = shift @_;
 my $name  = shift @_;
 my $key   = shift @_;
 my $value = shift @_;

 $value = 'true' if ($mode =~ m/context$/ && !defined $value);

 ensure_node_exists($db, $name);
 ensure_kv_valid($mode, $key, $value);

 my $vkey;

 $vkey = 'vars'             if $mode eq 'set';
 $vkey = 'contexts'         if $mode eq 'set-context';
 $vkey = 'learned_vars'     if $mode eq 'learn';
 $vkey = 'learned_contexts' if $mode eq 'learn-context';

 die "Sorry, I don't know how to handle general set mode $mode.  This is a bug."
  unless $vkey;

 # TODO: handle augment/decrement
 my $d = eval_any_json($value);

 ensure_v_is_context($mode, $value, $d)
  if $mode =~ m/context$/;

 $db->{nodes}->{$name}->{$vkey}->{$key} = $d;
 push @modified, $name;

 print "DONE: $mode $name $key '$value'\n"
  unless $quiet;
}

sub general_unset
{
 my $mode  = shift @_;
 my $db    = shift @_;
 my $name  = shift @_;
 my $key   = shift @_;

 ensure_node_exists($db, $name);
 ensure_k_valid($mode, $key);

 my $vkey;

 $vkey = 'vars'             if $mode eq 'unset';
 $vkey = 'contexts'         if $mode eq 'unset-context';
 $vkey = 'learned_vars'     if $mode eq 'unlearn';
 $vkey = 'learned_contexts' if $mode eq 'unlearn-context';

 die "Sorry, I don't know how to handle general unset mode $mode $name $key.  This is a bug."
  unless $vkey;

 die "Sorry, but we can't $mode $name $key because $name doesn't have it."
  unless exists $db->{nodes}->{$name}->{$vkey}->{$key};

 delete $db->{nodes}->{$name}->{$vkey}->{$key};
 push @modified, $name;

 print "DONE: $mode $name $key\n"
  unless $quiet;
}

sub is_json_boolean
{
 return ((ref shift) =~ m/JSON.*Boolean/);
}

# TODO: from cf-sketch.pl, should be extracted to a module!
sub recurse_print
{
 my $ref             = shift @_;
 my $prefix          = shift @_;
 my $unquote_scalars = shift @_;

 my @print;
                      # $_->{path},
                      # $_->{type},
                      # $_->{value}) foreach @toprint;

 # recurse for hashes
 if (ref $ref eq 'HASH')
 {
  push @print, recurse_print($ref->{$_}, $prefix . "[$_]", $unquote_scalars)
   foreach sort keys %$ref;
 }
 elsif (ref $ref eq 'ARRAY')
 {
  push @print, {
                path => $prefix,
                type => 'slist',
                value => '{' . join(", ", map { "\"$_\"" } @$ref) . '}'
               };
 }
 else
 {
  # convert to a 1/0 boolean
  $ref = ! ! $ref if is_json_boolean($ref);
  push @print, {
                path => $prefix,
                type => 'string',
                value => $unquote_scalars ? $ref : "\"$ref\""
               };
 }

 return @print;
}

sub resolve_contents
{
 return resolve_interpolations(resolve_inheritance(@_));
}

# this is fairly primitive, resolving only scalars and only once
sub resolve_interpolations
{
 my $data = shift @_;
 return $data unless ref $data eq 'HASH';

 foreach my $c (@data_containers)
 {
  foreach my $k (keys %{$data->{$c}})
  {
   my $v = $data->{$c}->{$k};

   if ($v =~ m/\$\(([^)]+)\)/ && $v ne $1)
   {
    my $symbol = $1;
    foreach my $c2 (@data_containers)
    {
     if (exists $data->{$c2}->{$symbol})
     {
      $data->{$c}->{$k} =~ s/\$\($symbol\)/$data->{$c2}->{$symbol}/g;
     }
    }
   }
  }
 }

 return $data;
}

sub resolve_inheritance
{
 my $db   = shift @_;
 my $name = shift @_;
 my @seen = @_;

 die "Uh-oh, inheritance cycle detected: @seen -> $name"
  if grep { $_ eq $name } @seen;

 my $v = eval_any_json($coder->encode($db->{nodes}->{$name}));
 my $ret = {};

 foreach my $parent (sort keys %{$v->{inherit}})
 {
  my $pres = resolve_inheritance($db, $parent, @seen, $name);

  die "Parent $parent did not produce valid data!"
   unless ref $pres eq 'HASH';

  foreach my $container (@containers)
  {
   die "Expected inheritance container $container not found in parent $parent!"
    unless ref $pres->{$container} eq 'HASH';

   foreach my $pk (keys %{$pres->{$container}})
   {
    my $ak = '=+'. $pk;
    my $dk = '=-'. $pk;
    my $written = 0;

    if (exists $v->{$container}->{$ak}) # augment
    {
     my $pv = eval_any_json($coder->encode($pres->{$container}->{$pk}));
     my $av = $v->{$container}->{$ak};
     die "Mismatched augmentation inheritance: parent $parent and node $name have different ideas about $container/$pk"
      if ref $pv ne ref $av;

     if (ref $av eq 'ARRAY')
     {
      $ret->{$container}->{$pk} = [ @$pv, @$av ];
     }
     elsif (ref $av eq 'HASH')
     {
      # No, I am NOT doing Hash::Merge or multi-level data merging.
      # If you want jim to handle that case, let me know.

      $ret->{$container}->{$pk}->{$_} = $pv->{$_} foreach keys %$pv;
      $ret->{$container}->{$pk}->{$_} = $av->{$_} foreach keys %$av;
     }
     else
     {
      die "Huh?  You are augmenting something besides a HASH or an ARRAY from parent $parent and node $name $container/$pk"
     }

     delete $v->{$container}->{$ak};
     $written = 1;
    }

    if (exists $v->{$container}->{$dk}) # decrement
    {
     # pv may already be set from above...
     my $pv = $ret->{$container}->{$pk} || eval_any_json($coder->encode($pres->{$container}->{$pk}));
     my $dv = $v->{$container}->{$dk};

     die "Mismatched decrement inheritance: parent $parent and node $name have different ideas about $container/$pk"
      if ref $pv ne ref $dv;

     if (ref $dv eq 'ARRAY')
     {
      my %filter = map { $_ => 1 } @$dv;
      $ret->{$container}->{$pk} = [grep { !exists $filter{$_} } @$pv];
     }
     elsif (ref $dv eq 'HASH')
     {
      $ret->{$container}->{$pk} = $pv;
      delete $ret->{$container}->{$pk}->{$_} foreach keys %$dv;
     }
     else
     {
      die "Huh?  You are augmenting something besides a HASH or an ARRAY from parent $parent and node $name $container/$pk"
     }

     delete $v->{$container}->{$dk};
     $written = 1;
    }

    unless ($written)
    {
     $ret->{$container}->{$pk} = $pres->{$container}->{$pk};
    }
   }
  }
 }

 foreach my $container (@containers)
 {
  $ret->{$container} ||= {};

  $ret->{$container}->{$_} = $v->{$container}->{$_}
   foreach keys %{$v->{$container}};
 }

 return $ret;
}

sub dirname_inherited
{
 my $db   = shift @_;
 my $name = shift @_;

ensure_node_exists($db, $name);
 my @parents = sort keys %{$db->{nodes}->{$name}->{inherit}};
 return "/$name" unless scalar @parents;

 my @printed_parents = map { dirname_inherited($db, $_) } @parents;

 return sprintf('%s%s%s/%s',
                scalar @parents > 1 ? '/{' : '',
                join(',', @printed_parents),
                scalar @parents > 1 ? '}' : '',
                $name);
}

sub dirnames_inherited
{
 my $db   = shift @_;
 my $name = shift @_;

 ensure_node_exists($db, $name);
 my @parents = sort keys %{$db->{nodes}->{$name}->{inherit}};
 return "/$name" unless scalar @parents;

 my @printed_parents = map { dirnames_inherited($db, $_) } @parents;

 return map { "$_/$name" } @printed_parents;
}

sub ls
{
 my $db       = shift @_;
 my $search   = shift @_;
 my $callback = shift @_;
 my @results;

 foreach my $term (@$search)
 {
  foreach my $name (keys %{$db->{nodes}})
  {
   my $node = $db->{nodes}->{$name};

   my $add;

   $add = $add || ($term eq $name);

   unless ($add)
   {
    foreach my $path (dirnames_inherited($db, $name))
    {
     $add = $add || (index($path, "$term") == 0);
    }
   }

   next unless $add;
   next if grep { $_->{name} eq $name } @results;

   $callback->($name, $node) if $callback;
   push @results, { name => $node, node => $node };
  }
 }

 return @results;
}

sub search
{
 my $db       = shift @_;
 my $search   = shift @_;
 my $callback = shift @_;
 my @results;

 foreach my $term (@$search)
 {
  foreach my $name (keys %{$db->{nodes}})
  {
   my $node = $db->{nodes}->{$name};

   my $add;

   $add = $add || ($name =~ m/$term/);
   $add = $add || (
                   $term =~ m/([^:]+):(.*)/ &&
                   (
                    (exists $node->{vars}->{$1} &&
                     $node->{vars}->{$1} eq $2) ||
                    (exists $node->{learned_vars}->{$1} &&
                     $node->{learned_vars}->{$1} eq $2)
                   )
                  );

   next unless $add;

   next if grep { $_->{name} eq $name } @results;
   $callback->($name, $node) if $callback;
   push @results, { name => $name, node => $node };
  }
 }

 return @results;
}

sub read_jim_db
{
  die "The database file $options{database} could not be found, use $0 --create"
   unless -f $options{database};

  die "The database file $options{database} was no readable"
   unless -r $options{database};

  @modified = ();
  return load_json($options{database});
}

sub write_jim_db
{
 my $f = shift;
 my $db = shift;

 my $mode = -f $f ? 'Rewrote' : 'Created';

 open(my $fh, '>', $f)
  or die "Could not write jim db file $f: $!";

 my $template = {
                 metadata => {},
                 rules => {},
                 nodes => {}
                };
 print $fh $coder->pretty(1)->encode($db || $template);

 close $fh;

 print "$mode jim db $f (@{[ scalar @modified]} changes).\n"
  unless $quiet;
 @modified = ();
}

__DATA__

Help for Jim

See README.md
