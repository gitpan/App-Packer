#!/usr/bin/perl -w

BEGIN { print "1..2\n" }

use B;

print "ok 1\n";

print "# OPf_KIDS: ", B::OPf_KIDS, "\n";

print "ok 2\n";
