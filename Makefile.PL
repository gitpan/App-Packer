#!/usr/bin/perl -w

use strict;
use Config;
use ExtUtils::Embed ();
use vars qw($ZLIB_LIB_DIR $ZLIB_INC_DIR $ZLIB_LINK_FLAGS $USE_ZLIB);

# set these to meaningful values if autodetection fails
$USE_ZLIB = undef;        # undef = try, 0 = disable, 1 = enable
$ZLIB_LIB_DIR = undef;    # e.g. /opt/zlib/lib
$ZLIB_INC_DIR = undef;    # e.g. /opt/zlib/include
$ZLIB_LINK_FLAGS = undef; # e.g. -L/opt/zlib/lib -lz

autodetect_zlib() if $USE_ZLIB || !defined $USE_ZLIB;

# this works around an anomaly in Debian (or EU::Embed, or whatever...)
my $ccopts;
my $ldopts;
sub ccopts { $ccopts }
sub ldopts { $ldopts }

BEGIN {
  $ccopts = ExtUtils::Embed::ccopts;
  $ldopts = ExtUtils::Embed::ldopts;
}

use ExtUtils::MakeMaker;

WriteMakefile( NAME          => 'App::Packer',
               ABSTRACT_FROM => 'lib/App/Packer.pm',
               VERSION_FROM  => 'lib/App/Packer.pm',
               AUTHOR        => 'Mattia Barbon <mbarbon@dsi.unive.it>',
               PREREQ_PM     => { 'Module::Info'             => 0.12_4,
                                  'File::Spec::Functions'    => 0.01,
                                  'Memoize'                  => 0.01,
                                  'Test::Harness::Straps'    => 0.14,
                                  'Config::IniFiles'         => 2,
                                },
               BINARY_LOCATION => 'App-Packer.tar.gz',
               # MakeMaker guesses wrong...
               NEEDS_LINKING => 0,
               EXE_FILES     => [ 'p2e.pl' ],
             );

package MY;

use Config;
use File::Spec::Functions qw(catfile catdir);

sub test {
  return <<'EOT'

test : all
	$(PERL) "-Mblib" "t/harness"

EOT
}

sub postamble {
  my $arch = catdir( qw(blib arch auto App Packer Backend DemoPack) );
  my $lib = catdir( qw(blib lib App Packer Frontend ModuleInfo) );
  my $emb = catfile( 'myldr', "embed$Config{_exe}" );
  my $embz = catfile( 'myldr', "embed_z$Config{_exe}" );

  return <<EOT;

all :: copy_embed copy_ini

copy_embed : subdirs
	\$(MKPATH) "$arch"
	\$(CP) "$emb" "$arch"
	\$(CP) "$embz" "$arch"

copy_ini : 
	\$(MKPATH) "$lib"
	\$(CP) "hints.ini" "$lib"

ppm : all
	tar cvf App-Packer.tar blib
	gzip -9 App-Packer.tar

EOT
}

package main;

use File::Spec::Functions qw(rel2abs catfile);

sub autodetect_zlib {
  if( !defined( $ZLIB_INC_DIR ) || !defined( $ZLIB_LIB_DIR ) ) {
    if( $^O eq 'MSWin32' ) {
      if( defined( my $d = glob( "zlib*" ) ) ) {
        $ZLIB_INC_DIR = $ZLIB_LIB_DIR = rel2abs( $d );
      }
    } else {
      unless( defined $ZLIB_INC_DIR ) {
        foreach my $d ( qw(/usr/include /usr/local/include) ) {
          my $h = catfile( $d, 'zlib.h' );
          if( -f $h ) {
            $ZLIB_INC_DIR = $d;
            last;
          }
        }
      }

      unless( defined $ZLIB_LIB_DIR ) {
        foreach my $d ( qw(/usr/lib /usr/local/lib) ) {
          if( defined glob( catfile( $d, 'libz.*' ) ) ) {
            $ZLIB_LIB_DIR = $d;
            last;
          }
        }
      }

    }
  }

  my $stars = "\n" . ( '*' x 45 ) . "\n";
  if( !defined( $ZLIB_INC_DIR ) || !defined( $ZLIB_LIB_DIR ) ) {
    warn "$stars\nZlib not found, compression support disabled\n$stars\n";
    $USE_ZLIB ||= 0;
  } else {
    warn "$stars\nZlib found, compression support enabled\n$stars\n";
    $USE_ZLIB ||= 1;
  }
}

# local variables:
# mode: cperl
# end;
