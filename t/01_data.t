#!/usr/bin/perl -w

my $skip = 0;

BEGIN {
  unless( $] >= 5.008 ) {
    print( "1..0 # Skip does not work without PerlIO\n" );
    $skip = 1;
  } else {
    print "1..2\n";
  }
}

exit 0 if $skip;

print <main::DATA>;

__DATA__
ok 1
ok 2
