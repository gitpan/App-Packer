#!/usr/bin/perl -w

use strict;
use Config;
use ExtUtils::MakeMaker;

WriteMakefile( NAME          => 'App::Packer',
               ABSTRACT_FROM => 'lib/App/Packer.pm',
               VERSION_FROM  => 'lib/App/Packer.pm',
               AUTHOR        => 'Mattia Barbon <mbarbon@dsi.unive.it>',
               PREREQ_PM     => { 'Module::Info'             => 0.12,
                                  'File::Spec::Functions'    => 0,
                                  'Memoize'                  => 0,
                                  'Test::Harness::Straps'    => 0.14,
                                  'Config::IniFiles'         => 2,
                                },
               BINARY_LOCATION => 'App-Packer.tar.gz',
               # MakeMaker guesses wrong...
               NEEDS_LINKING => 0,
             );

package MY;

use Config;
use File::Spec::Functions qw(catfile catdir);

sub test {
  return <<'EOT'

test: all
	$(PERL) "-Mblib" "t/harness"

EOT
}

sub postamble {
  my $arch = catdir( qw(blib arch auto App Packer Backend DemoPack) );
  my $lib = catdir( qw(blib lib App Packer Frontend ModuleInfo) );
  my $emb = catfile( 'myldr', "embed$Config{_exe}" );

  return <<EOT;

all :: copy_embed copy_ini

copy_embed : subdirs
	\$(MKPATH) "$arch"
	\$(CP) "$emb" "$arch"

copy_ini : 
	\$(MKPATH) "$lib"
	\$(CP) "hints.ini" "$lib"

ppm : all
	tar cvf App-Packer.tar blib
	gzip -9 App-Packer.tar

EOT
}

# local variables:
# mode: cperl
# end;
