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
  augment    => 0,
  decrement  => 0,

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
  "augment|a!",
  "decrement|d!",
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
 write_jim_template($options{database});
 exit;
}

my %handlers = (
                # jim ls
                ls => sub
                {
                 my $db = shift @_;
                 my @search = @_;
                 die "TODO: ls @search";
                },
                # jim ls-json
                'ls-json' => sub
                {
                 my $db = shift @_;
                 my @search = @_;
                 die "TODO: ls-json @search";
                },

                # # set/learn attribute b in node a (set == learn for the below, except tags)
                # jim set a:b '"c"'
                # jim set a:b '[ "c" ]'
                # jim set a:b '{ c: "d" }'
                # # set takes --augment and --decrement (-a and -d) to indicate that instead of override, we should add or subtract attributes
                set => sub
                {
                 my $db = shift @_;
                 my @data = @_;
                 die "TODO: set @data";
                },

                learn => sub
                {
                 my $db = shift @_;
                 my @data = @_;
                 die "TODO: learn @data";
                },

                # jim set_context a:b 1 or 0 or '"cfengine expression"'
                set_context => sub
                {
                 my $db = shift @_;
                 my @data = @_;
                 die "TODO: set_context @data";
                },

                learn_context => sub
                {
                 my $db = shift @_;
                 my @data = @_;
                 die "TODO: learn_context @data";
                },

                # # add a node with parents a and b; node names are unique
                # jim add node1 a b
                add => sub
                {
                 my $db = shift @_;
                 my $name = shift @_;
                 my @parents = @_;

                 die "Non-empty node name must be given to 'add', sorry"
                  unless $name;

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
                                          tags => {},
                                          inherit => { map { $_ => {} } @parents }
                                         };
                 print "Added new node $name with parents [@parents]\n"
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

                  print "Removed node $name\n"
                   unless $quiet;
                 }
                },
               );

my %output_handlers = (
                       cfmodule => sub
                       {
                        my $db = shift @_;
                        my $name = shift @_;
                        die "TODO: cfmodule output of $name";
                       },

                       json => sub
                       {
                        my $db = shift @_;
                        my $name = shift @_;
                        die "TODO: JSON output of $name";
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

write_jim_template($options{database}, $db)
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
  # format:  { learned_vars: {}, vars: {}, learned_contexts: {}, contexts: {}, tags: {}, inherit: { "x": {}, "y": { augment: ["arrayZ"] } } }
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

sub write_jim_template
{
 my $f = shift;
 my $db = shift;

 my $mode = -f $f ? 'Rewrote' : 'Created';

 open(my $fh, '>', $f)
  or die "Could not write template file $f: $!";

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
