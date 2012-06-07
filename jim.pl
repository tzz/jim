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
  augment    => [],
  decrement  => [],

  database   => "jim.json"
 );

my @options_spec =
 (
  "quiet|q!",
  "help!",
  "verbose|v!",
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

my %handlers = (
                # jim ls [node]
                ls => sub
                {
                 my $db = shift @_;
                 my @search = @_;
                 die "TODO: ls @search";

                 my @results;
                 exit !scalar @results;
                },

                # jim ls-json [node]
                'ls-json' => sub
                {
                 my $db = shift @_;
                 my @search = @_;
                 die "TODO: ls-json @search";

                 my @results;
                 exit !scalar @results;
                },

                # jim search TERM1 [and|or TERM2] [and|or TERM3]
                search => sub
                {
                 my $db = shift @_;
                 my @search = @_;
                 die "TODO: search @search";

                 my @results;
                 exit !scalar @results;
                },

                # # set/learn attribute b in node a (set == learn for the below)
                # # all of these have unset/unlearn counterparts
                # jim set a b '"c"'
                # jim set a b '[ "c" ]'
                # jim set a b '{ c: "d" }'
                set => sub
                {
                 general_set('set', @_);
                },

                learn => sub
                {
                 general_set('learn', @_);
                },

                # jim set-context a b 1 or 0 or '"cfengine expression"'
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

                # # add a node with parents a and b; node names are unique
                # jim add node1 a b
                add => sub
                {
                 my $db = shift @_;
                 my $name = shift @_;
                 my @parents = @_;

                 ensure_name_valid($db, $name);

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
                 print "DONE: add $name @parents\n"
                  unless $quiet;
                },

                # jim rm node1
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

                  validate_db($db);

                 print "DONE: rm $name\n"
                  unless $quiet;
                 }
                },
               );

my %output_handlers = (
                       cfmodule => sub
                       {
                        my $db = shift @_;
                        my $name = shift @_;

                        ensure_name_valid($db, $name);

                        foreach my $context_topk (qw/contexts learned_contexts/)
                        {
                         my %chash = %{$db->{nodes}->{$name}->{$context_topk}};
                         my $prefix = ($context_topk eq 'contexts') ? '' : 'learned_';

                         foreach my $key (sort keys %chash)
                         {
                          my $v = $chash{$key};
                          if (ref $v) # a boolean
                          {
                           print "+${prefix}$key\n" if $v;
                          }
                          else  # a string or number
                          {
                           print "=${prefix}bycontext[$key]=$v\n";
                          }
                         }
                        }

                        foreach my $var_topk (qw/vars learned_vars/)
                        {
                         my %vhash = %{$db->{nodes}->{$name}->{$var_topk}};
                         my $prefix = ($var_topk eq 'vars') ? '' : 'learned_';

                         foreach my $k (sort keys %vhash)
                         {
                          foreach my $p (recurse_print($vhash{$k},
                                                       "${prefix}$k",
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

                        ensure_name_valid($db, $name);
                        print $coder->encode($db->{nodes}->{$name});
                       },

                       yaml => sub
                       {
                        my $db = shift @_;
                        my $name = shift @_;
                        die "TODO: YAML output of $name";
                       },
                      );

my $db = validate_db();
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
  die "The database file $options{database} could not be found, use $0 --create"
   unless -f $options{database};

  die "The database file $options{database} was no readable"
   unless -r $options{database};

  $db = load_json($options{database});
 }

 die "Bad database $options{database}: not a hash!"
  unless ref $db eq 'HASH';

 foreach (qw/metadata nodes/)
 {
  die "Bad database $options{database}: no '$_' key!"
   unless exists $db->{$_};

  die "Bad database $options{database}: '$_' value should be a hash!"
   unless ref $db->{$_} eq 'HASH';
 }

 my %nodes = %{$db->{nodes}};
 foreach my $node (sort keys %nodes)
 {
  my $v = $nodes{$node};
  # format:  { learned_vars: {}, vars: {}, learned_contexts: {}, contexts: {}, inherit: { "x": {}, "y": { augment: ["arrayZ"] } } }
  die "Node $node: record is not a hash" unless ref $v eq 'HASH';

  foreach (qw/learned_vars vars learned_contexts contexts tags inherit/)
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

sub ensure_name_valid
{
 my $db = shift @_;
 my $name = shift @_;

 die "Non-empty node name must be given, sorry"
  unless $name;
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

 ensure_name_valid($db, $name);
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

 print "DONE: $mode $name $key '$value'\n"
  unless $quiet;
}

sub general_unset
{
 my $mode  = shift @_;
 my $db    = shift @_;
 my $name  = shift @_;
 my $key   = shift @_;

 ensure_name_valid($db, $name);
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
  push @print, recurse_print($ref->{$_}, $prefix . "[$_]")
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
  $ref = ! ! $ref if is_json_boolean($ref)
  push @print, {
                path => $prefix,
                type => 'string',
                value => $unquote_scalars ? $ref : "\"$ref\""
               };
 }

 return @print;
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
                 nodes => {}
                };
 print $fh $coder->pretty(1)->encode($db || $template);

 close $fh;

 print "$mode jim db $f.\n"
  unless $quiet;
}

__DATA__

Help for Jim

See README.md
