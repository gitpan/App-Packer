#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use App::Packer;

my $out_file = 'my';
my $run_exe = 0;
my $help = @ARGV == 0;
my @extra_modules;

my $result = GetOptions( 'output-file=s' => \$out_file,
                         'run-exe'       => \$run_exe,
                         'help'          => \$help,
                         'add-module=s'  => \@extra_modules );

my $script = shift @ARGV;

if( !$result || $help || @ARGV != 0 ) {
  print <<EOT;
Usage: perl p2e.pl [options] script-file.pl
    --output-file=file  final executable
    --run-exe           run the executable after writing it
    --help              you are reading it
    --add-module        add the module to the exe
                        (can be used multiple times)
EOT
  exit !$result;
}

my $packer = App::Packer->new;
$packer->set_file( $script );

my %fe_options;
$fe_options{add_modules} = \@extra_modules if @extra_modules;
$packer->set_options( frontend => \%fe_options );

my $exe = $packer->write( $out_file );

if( $run_exe ) { system $^O eq 'MSWin32' ? "$exe" : "./$exe" }

exit 0;

# local variables:
# mode: cperl
# end:
