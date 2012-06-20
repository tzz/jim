# EC2 plugin: provides the ec2 command

use VM::EC2;
use strict;
use warnings;

foreach my $required_env (qw/EC2_INSTANCE_SSH_RSA_KEY EC2_ACCESS_KEY EC2_SECRET_KEY/)
{
 die "Sorry, we can't go on until you've set the environment variable $required_env"
  unless defined $ENV{$required_env};

 if (-r $ENV{$required_env})
 {
  open my $ef, '<', $ENV{$required_env} or die "Could not open environment pass-through file $ENV{$required_env}: $!";
  my $line = <$ef>;
  chomp $line;
  $ENV{$required_env} = $line;
 }
}

my $ec2 = VM::EC2->new(-endpoint => 'http://ec2.amazonaws.com');

return sub
{
 my $db = shift @_;
 my $command = shift @_;
 my @args = @_;

 if ($command eq 'control')
 {
  print "ec2 controlling @args\n";
  my ($target_count, $client_class, @rest) = @args;

  my %ec2_options = (
                     hub => undef,
                     ami => undef,
                     type => 'm1.small',
                     region => 'us-east-1',
                     security_group => 'default',
                    );

  foreach my $option (@rest)
  {
   foreach my $k (keys %ec2_options)
   {
    next unless $option=~ m/^$k=(.+)$/;
    $ec2_options{$k} = $1;
   }
  }

  die "Not enough arguments given to 'ec2 $command': expecting TARGET_COUNT CLIENT_CLASS [hub=HUB_IP|ami=AMI_NAME|type=INSTANCE_TYPE|region=REGION|security_group=SECURITY_GROUP]"
   unless defined $client_class;

   foreach my $k (keys %ec2_options)
   {
    die "Required option '$k=VALUE' not given to 'ec2 $command'"
     unless defined $ec2_options{$k};
   }

  my $image = $ec2->describe_images($ec2_options{ami});

  # get some information about the image
  my $architecture = $image->architecture;
  my $description  = $image->description || '';
  print "Using image $image with architecture $architecture (desc: '$description')\n";

  my $public_key = $ENV{EC2_INSTANCE_SSH_RSA_KEY};
  die "No public key available in environment variable EC2_INSTANCE_SSH_RSA_KEY, please set it"
   unless $public_key;

  my $key = $ec2->import_key_pair('jim-ec2-key', $public_key);

  my @current_instances = find_tagged_ec2_instances($client_class);

  my $delta = $target_count - scalar @current_instances;

  if ($delta > 0)
  {
   my $go = ec2_init_script($ec2_options{hub}, $client_class);
   my @instances = $image->run_instances(-key_name      =>'jim-ec2-key',
                                         -security_group=> $ec2_options{security_group},
                                         -min_count     => $delta,
                                         -max_count     => $delta,
                                         -user_data     => "#!/bin/sh -ex\n$go",
                                         -region        => $ec2_options{region},
                                         -client_token  => $ec2->token(),
                                         -instance_type => $ec2_options{type})
    or die $ec2->error_str;

   print "waiting for ", scalar @instances, " instances to start up...";
   $ec2->wait_for_instances(@instances);
   print "done!\n";

   foreach my $i (@instances)
   {
    my $status = $i->current_status;
    my $dns    = $i->dnsName;
    print "Started instance $i $dns $status\n";
    my $name = "ec2 instance of class $client_class created by jim EC2 plugin";
    $i->add_tag(cfclass => $client_class,
                Name    => $name);
    print "Tagged instance $i: Name = '$name', cfclass = $client_class\n";
   }
  }
  elsif ($delta == 0)
  {
    print "Nothing to do, we have $target_count instances already\n";
  }
  else                                  # delta < 0, we need to decom
  {
   while ($delta < 0)
   {
    my $todo = shift @current_instances;
    stop_and_terminate_ec2_instances([$todo]);
    $delta++;
   }
  }
 }
 elsif ($command eq 'down')
 {
  my $client_class = shift @args;

  die "Not enough arguments given to 'ec2 $command': expecting CLIENT_CLASS"
   unless defined $client_class;

  my @instances = find_tagged_ec2_instances($client_class);
  if (scalar @instances)
  {
   stop_and_terminate_ec2_instances(\@instances);
  }
 }
 elsif ($command eq 'run')
 {
  my $client_class = shift @args;
  my $command = shift @args;

  die "Not enough arguments given to 'ec2 $command': expecting CLIENT_CLASS COMMAND"
   unless defined $command;

  my @instances = find_tagged_ec2_instances($client_class);
  if (scalar @instances)
  {
   system ("$command " . $_->dnsName) foreach @instances;
  }
 }
 elsif ($command eq 'list' || $command eq 'console' || $command eq 'console-tail' || $command eq 'list-full' || $command eq 'count')
 {
  my $client_class = shift @args;

  die "Not enough arguments given to 'ec2 $command': expecting CLIENT_CLASS"
   unless defined $client_class;
  my @instances = find_tagged_ec2_instances($client_class);
  if ($command eq 'count')
  {
   print scalar @instances, "\n";
  }
  elsif ($command eq 'console')
  {
   foreach my $i (@instances)
   {
    my $out = $i->console_output;
    my $dns    = $i->dnsName;
    print "$i $dns\n$out\n\n";
   }
  }
  elsif ($command eq 'console-tail')
  {
   while (1)
   {
    foreach my $i (@instances)
    {
     my $out = $i->console_output;
     my $dns    = $i->dnsName;
     print "$i $dns\n$out\n\n";
    }
   }
   print "Press Ctrl-C to abort the tail...";
  }
  elsif ($command eq 'list-full')
  {
   foreach my $i (@instances)
   {
    my $status = $i->current_status;
    my $dns    = $i->dnsName;
    print "$i $dns $status\n";
   }
  }
  else
  {
   print join("\n", @instances), "\n";
  }
 }
 else
 {
  print "unknown ec2 command: $command @args\n";
 }
};

sub find_tagged_ec2_instances
{
 my $tag = shift @_;
 my $state = shift @_ || 'running';

 return $ec2->describe_instances(-filter => {
                                             'instance-state-name'=>$state,
                                             'tag:cfclass' => $tag
                                            });
}

sub stop_and_terminate_ec2_instances
{
 my $instances = shift @_;

 my @instances = @$instances;

 print "Stopping instances @instances...";
 $ec2->stop_instances(-instance_id=>$instances,-force=>1);
 $ec2->wait_for_instances(@instances);
 print "done!\n";

 print "Terminating instances @instances...";
 $ec2->terminate_instances(-instance_id=>$instances,-force=>1);
 $ec2->wait_for_instances(@instances);
 print "done!\n";
}

sub ec2_init_script
{
 my $hub_ip = shift @_;
 my $client_class = shift @_;

 return "

echo '$hub_ip' > /var/tmp/cfhub.ip
echo '$client_class' > /var/tmp/cfclass
echo 'jim_ec2' >> /var/tmp/cfclass

# the cfengine repo doesn't work yet

curl -o /tmp/cfengine.gpg.key http://cfengine.com/pub/gpg.key

apt-key add /tmp/cfengine.gpg.key

add-apt-repository http://cfengine.com/pub/apt

apt-get update || echo anyways...

# apt-get install -y --force-yes cfengine-community || echo anyways...

# this is version 3.1.5, quite old!
apt-get install cfengine3

" . ec2_client_init_script($client_class);

}

sub ec2_client_init_script
{
 # from JH's magic
 return '
LOG=/tmp/jim.ec2.cfengine.setup.log

cat >> /tmp/set_persistent_classes.cf << EOF;
body common control {
  bundlesequence => { "set_persistent_classes" };
  nova_edition|constellation_edition::
    host_licenses_paid => "1";
}

bundle agent set_persistent_classes {
  vars:
    "classes" slist => readstringlist("/var/tmp/cfclass", "#[^n]*", "\s*\n\s*", "100000", "99999999999");
    "now" int => ago(0,0,0,0,0,0);
  reports:
    cfengine_3::
      "\$(classes) \$(now)"
        classes => if_repaired_persist_forever("\$(classes)");
}
body classes if_repaired_persist_forever(class) {
  promise_repaired => { "\$(class)" };
  persist_time => "48417212";
  timer_policy => "reset";
}
EOF

cf-agent -KI -f /tmp/set_persistent_classes.cf >> $LOG 2>&1

rm -rf /tmp/set_persistent_classes.cf

# Bootstrap to the policy hub 
# rm -rf /var/cfengine/inputs

cf-agent -B -s `cat /var/tmp/cfhub.ip` >> $LOG 2>&1
';
}
