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
 elsif ($command eq 'start')
 {
  print "ec2 starting @args\n";
 }
 elsif ($command eq 'stop')
 {
  print "ec2 stopping @args\n";
 }
 elsif ($command eq 'list')
 {
  print "ec2 stopping @args\n";
 }
 else
 {
  print "unknown ec2 command: $command @args\n";
 }
};
