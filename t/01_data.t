#!/usr/bin/perl -w

BEGIN {
  print "1..0 # Skip does not work without PerlIO\n"
    unless $] >= 5.008;
  print "1..2\n";
}
print <main::DATA>;

__DATA__
ok 1
ok 2
