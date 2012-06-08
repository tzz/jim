# EC2 plugin: provides the ec2 command

return sub
{
 my $db = shift @_;
 my $command = shift @_;
 my @args = @_;
 if ($command eq 'bootstrap')
 {
  print "ec2 bootstrapping @args\n";
 }
 elsif ($command eq 'init')
 {
  print "ec2 initializing @args\n";
 }
 elsif ($command eq 'deinit')
 {
  print "ec2 deinitializing @args\n";
 }
 elsif ($command eq 'launch')
 {
  print "ec2 launching @args\n";
 }
 else
 {
  print "unknown ec2 command: $command @args\n";
 }
};
