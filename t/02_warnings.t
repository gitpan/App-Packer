#!/usr/bin/perl -w

BEGIN { print "1..1\n" }

my( $nok, $a ) = 'not ';

$SIG{__WARN__} = sub { $nok = '' };

$a .= undef;

print "${nok}ok 1\n";
