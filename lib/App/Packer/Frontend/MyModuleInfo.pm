package App::Packer::Frontend::MyModuleInfo;

use strict;
use base 'Module::Info';
use File::Spec::Functions qw(catfile catdir);
use Memoize;
use Config;
use Fcntl;
use Memoize::SDBM_File;
use File::Path;
use File::stat;

my $cache_base = $ENV{HOME} || $ENV{TEMP} || $ENV{TMP};
my $cache_dir = catdir( $cache_base, '.packer' );
my $modules_file = catfile( $cache_dir, 'modules_used' );
my $superclasses_file = catfile( $cache_dir, 'superclasses' );

mkpath( $cache_dir ) unless -d $cache_dir;

my( %modules_used, %superclasses );
tie %modules_used, 'Memoize::SDBM_File',
  $modules_file, O_RDWR|O_CREAT, 0666
  or die "Can't create cache file: $!";
tie %superclasses, 'Memoize::SDBM_File',
  $superclasses_file, O_RDWR|O_CREAT, 0666
  or die "Can't create cache file: $!";

# SDBM_File can't store arrays, hence we store join '!', @modules
# in the hope that module names do not contain '!'
# the key value is the full path of the file plus the modification time
memoize( 'modules_used_xx',
         SCALAR_CACHE => [ 'HASH', \%modules_used ],
         NORMALIZER => sub {
           my $file = $_[0]->file;
           my $stat = stat( $file ) or die "stat: $!";

           return $file . "\0" . $stat->mtime;
         },
       );

memoize( 'superclasses_xx',
         SCALAR_CACHE => [ 'HASH', \%superclasses ],
         NORMALIZER => sub {
           my $file = $_[0]->file;
           my $stat = stat( $file ) or die "stat: $!";

           return $file . "\0" . $stat->mtime;
         },
       );

sub modules_used_xx {
  my $this = shift;
  return join '!', $this->SUPER::modules_used;
}

sub modules_used {
  return split '!', modules_used_xx( $_[0] );
}

sub superclasses {
  return split '!', superclasses_xx( $_[0] );
}

sub superclasses_xx {
  my $this = shift;
  # warn $this->name;
  return join '!', $this->SUPER::superclasses;
}

# find the 'auto' diretory; should probably use $Config for more safety,
# but this suffices for now
#
# RETURN VALUE
#   path to the 'auto' directory, undef on failure
sub _auto_dir {
  my $this = shift;
  my $inc = $this->inc_dir;
  my $name = $this->name;
  my $auto_dir = catdir( $inc, 'auto', split( '::', $name ) );

  return -d $auto_dir ? $auto_dir : undef;
}

# RETURN VALUE
#   true is module uses AutoLoader, false otherwise
sub uses_autoload {
  my $this = shift;
  my @used = $this->modules_used;

  return scalar grep { $_ eq 'AutoLoader' } @used;
}

# RETURN VALUE
#   returns a list containing the .al files for the module
#   if it can't find the directory it returns the empty list,
#   on the basis that a module _may_ require AutoLoader without
#   using it (probably a broken module...)
sub autoload_files {
  my $this = shift;
  my $al_dir = $this->_auto_dir;

  return unless $al_dir;
  return glob( catfile( $al_dir, '*.al' ) ),
         glob( catfile( $al_dir, '*.ix' ) );
}

# RETURN VALUE
#   true if the module appears to use dynamic loading, false otherwise.
sub uses_dynamic_loading {
  my $this = shift;
  my @used = $this->modules_used;

  return scalar grep { $_ eq 'DynaLoader' || $_ eq 'XSLoader' } @used;
}

# RETURN VALUE
#   returns the DLL/so/whatever loaded by the module
sub dynamic_loading_file {
  my $this = shift;
  my $al_dir = $this->_auto_dir;
  return unless $al_dir;
  my @dl = glob( catfile( $al_dir, "*.$Config{dlext}" ) );

  return $dl[0];
}

package App::Packer::Frontend::MyModuleInfo::Hints;

use base 'App::Packer::Frontend::MyModuleInfo';

sub set_hints {
  my( $this, $ini ) = @_;
  my $name = $this->name;

  $this->{HINTS} = {};

  return unless $ini->SectionExists( $name );

  $this->{HINTS}{U_D_L} = $ini->val( $name, 'uses_dynamic_loading' );
  $this->{HINTS}{M_U} = [ $ini->val( $name, 'modules_used' ) ]
    if defined( $ini->val( $name, 'modules_used' ) );
}

sub modules_used {
  my $this = shift;
  my @used = $this->SUPER::modules_used;

  if( defined $this->{HINTS}{M_U} ) { push @used, @{$this->{HINTS}{M_U}} }
  return @used;
}

sub uses_dynamic_loading {
  my $this = shift;

  if( defined $this->{HINTS}{U_D_L} ) { return $this->{HINTS}{U_D_L} }
  return $this->SUPER::uses_dynamic_loading;
}

1;

# local variables:
# mode: cperl
# end:
