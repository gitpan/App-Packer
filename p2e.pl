#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use App::Packer;

Getopt::Long::Configure( "no_ignore_case" );

my $out_file = 'my';
my $run_exe = 0;
my $help = @ARGV == 0;
my @extra_modules;
my $verbose = 1;
my $frontend = 'App::Packer::Frontend::ModuleInfo';
my $backend = 'App::Packer::Backend::DemoPack';

my $result = GetOptions( 'output-file=s' => \$out_file,
                         'run-exe'       => \$run_exe,
                         'help'          => \$help,
                         'add-module=s'  => \@extra_modules,
                         'M=s'           => \@extra_modules,
                         'verbose+'      => \$verbose,
                         'quiet'         => sub { $verbose = 0 },
                         'frontend=s'    => \$frontend,
                         'backend=s'     => \$backend,
                       );

my $script = shift @ARGV;

if( !$result || $help || @ARGV != 0 ) {
  print <<EOT;
Usage: perl p2e.pl [options] script-file.pl
    -o --output-file=file  final executable
    -r --run-exe           run the executable after writing it
    -h --help              you are reading it
       --add-module        add the module to the exe
                           (can be used multiple times)
    -v --verbose           be verbose (can be used multiple times)
    -q --quiet             don't be verbose
    -f --frontend package  which frontend to use
    -b --backend package   which backend to use
EOT
  exit !$result;
}

sub do_require($) {
  my $file = shift;
  $file =~ s{::}{/}g;
  $file .= '.pm';

  require $file;
}

do_require $frontend;
do_require $backend;

my $packer = App::Packer->new( frontend => $frontend,
                               backend  => $backend,
                              );
$packer->set_file( $script );

my( %fe_options, %be_options );
$fe_options{add_modules} = \@extra_modules if @extra_modules;
$fe_options{verbose} = $verbose;
$be_options{verbose} = $verbose;

$packer->set_options( frontend => \%fe_options,
                      backend  => \%be_options,
                    );

my $exe = $packer->write( $out_file );

if( $run_exe ) { system $^O eq 'MSWin32' ? "$exe" : "./$exe" }

exit 0;

# local variables:
# mode: cperl
# end:
