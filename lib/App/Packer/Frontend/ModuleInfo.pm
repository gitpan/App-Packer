package App::Packer::Frontend::ModuleInfo;

use strict;
use vars '$VERSION';
use App::Packer::Frontend::MyModuleInfo;
use File::Spec::Functions qw(catdir catfile file_name_is_absolute);
use File::Basename;
use Config;

$VERSION = '0.08';

my $modinfo_class = 'App::Packer::Frontend::MyModuleInfo';
# the default hints file
my $root_hints_file;
my $root_hints_object;

{
  # search for the hints file in blib, then system directories
  my @dirs = ( $Config{installprivlib}, $Config{installsitelib},
               $Config{installarchlib}, $Config{installsitearch} );
  my $blib = catdir( qw(blib lib) );

  foreach my $d ( $blib, @dirs ) {
    my $f = catfile( $d, split( '::', __PACKAGE__ ), 'hints.ini' );
    if( -f $f ) { $root_hints_file = $f; last }
  }

  warn "Hints file not found" unless $root_hints_file;
}

sub new {
  my $ref = shift;
  my $class = ref( $ref ) || $ref;
  my $this = bless {}, $class;

  return $this;
}

sub set_file {
  my $this = shift;
  my $file = shift;

  return unless -f $file;

  $this->{FILE} = $file;
  $this->{FILES}->{MAIN} = { file     => $file,
                             store_as => basename( $file ) };

  return 1;
}

sub set_options {
  my $this = shift;
  my %args = @_;

  $this->{EXTRA_MODULES} = $args{add_modules};
  $this->{VERBOSE}       = $args{verbose} || 0;
}

sub _verbose { $_[0]->{VERBOSE} }

# $this->_get_hints();
#
# return a Config::IniFiles object initialised with hints.ini
sub _get_hints {
  return unless $root_hints_file;
  my $this = shift;

  require Config::IniFiles;
  $root_hints_object = Config::IniFiles->new( '-file' => $root_hints_file )
    unless $root_hints_object;
  die "Unable to read INI file '$root_hints_file", @Config::IniFiles::errors
    unless $root_hints_object;
  $this->{HINTS} = $root_hints_object;
}

# $this->_set_extra_modules( $module_info );
#
# call $module_info->extra_modules( ... ) if the hints file says so
sub _set_extra_modules {
  my $this = shift;
  my $info = shift;
  my $hints = $this->_get_hints;

  if( $hints && $hints->SectionExists( 'prerequisites' ) ) {
    foreach my $param ( $hints->Parameters( 'prerequisites' ) ) {
      my( $re, @mods ) = $hints->val( 'prerequisites', $param );

      $info->extra_modules( @mods ) if $info->name =~ m/$re/;
    }
  }
}

# $this->_get_info_object( $file_or_module );
#
# simple wrapper for Module::Info->new_.*( ... );
sub _get_info_object {
  my $this = shift;
  my $module = shift;
  my $path = $module;
  my $method = ( $module =~ m/\.\w+$/ ? 'new_from_file' : 'new_from_module' );
  my $info;

  if( $method eq 'new_from_file' && !file_name_is_absolute( $module ) ) {
    foreach my $d ( @INC ) {
      my $abs = catfile( $d, $module );
      if( -f $abs ) {
        $path = $abs;
        last;
      }
    }
  }

  if( $this->{HINTS} && $this->{HINTS}->SectionExists( $module ) ) {
    $info = App::Packer::Frontend::MyModuleInfo::Hints
      ->$method( $path );
    $info->set_hints( $this->{HINTS} ) if $info;
  } else {
    $info = $modinfo_class->$method( $path );
  }

  unless( defined $info ) {
    warn "Error while creating Module::Info object for '$module'"
      if $this->_verbose >= 0;
    return;
  }

  $info->die_on_compilation_error( 1 );
  $this->_set_extra_modules( $info );

  return $info;
}

# $this->_skip( $module_name );
#
# true if the [skip] section mentions this module
sub _skip {
  my $this = shift;
  my $module = shift;

  if( !defined $this->{SKIP} ) {
    my $hints = $this->_get_hints;
    my %skip;

    if( $hints && $hints->SectionExists( 'skip' ) ) {
      foreach my $p ( $hints->Parameters( 'skip' ) ) {
        my @mods = $hints->val( 'skip', $p );
        @skip{@mods} = @mods;
      }
    }

    $this->{SKIP} = \%skip;
  }

  return exists $this->{SKIP}{$module};
}

sub _info_for_module {
  my $this = shift;
  my $module = shift;
  my $required_by = shift;

  # skip module if necessary
  return if $this->_skip( $module );

  # if this module has already been required by some other module,
  # just update its 'used_by' field
  if( exists $this->{FILES}->{MODULES}->{$module} && $required_by ) {
    my $used_by = $this->{FILES}->{MODULES}->{$module}->{used_by} ||= [];
    # paranoia; don't add modules twice
    push @$used_by, $required_by
      unless grep { $_ eq $required_by } @$used_by;

    return;
  }

  # do the real work
  my $info = $this->_get_info_object( $module ) || return;

  print "Processing '$module'\n" if $this->_verbose >= 1;

  # @used may have duplicate entries, clean them up!
  my @used = ( $info->modules_used, $info->superclasses );
  my $file = $info->file;
  # store Foo::Bar as Foo/Bar.pm
  my $store_as = ( $module =~ m{/} ) ?
                             $module :
    ( join '/', split '::', $module ) . '.pm';
  my %used; @used{@used} = @used; @used = keys %used; # eliminate duplicates

  my $mobject =
    $this->{FILES}->{MODULES}->{$module} = { file     => $file,
                                             store_as => $store_as };
  $mobject->{used_by} = [ $required_by ]
    if defined $required_by;

  # if the module uses autoloading
  if( $info->uses_autoload ) {
    my @al_files = $info->autoload_files;

    # strip anything preceding the 'auto' directory
    foreach my $a ( @al_files ) {
      # store .al file for Foo::Bar as auto/Foo/Bar/x.al
      my $fname = File::Basename::basename( $a );
      my $path = join '/', 'auto', split( '::', $info->name ), $fname;

      push @{$this->{FILES}->{AUTOLOAD}->{$module}},
        { file     => $a,
          store_as => $path,
          used_by  => [ $mobject ] };
    }
  }

  # if the uses dynamic loading
  if( $info->uses_dynamic_loading ) {
    my $dl_file = $info->dynamic_loading_file;

    if( $dl_file ) {
      # strip anything preceding the 'auto' directory
      # store the file as auto/Foo/Bar/Bar.dll
      my $fname = File::Basename::basename( $dl_file );
      my $path = join '/', 'auto', split( '::', $info->name ), $fname;

      push @{$this->{FILES}->{SHARED}->{$module}},
        { file     => $dl_file,
          store_as => $path,
          used_by  => [ $mobject ] };
    }
  }

  # now go recursively
  foreach my $m ( @used ) { $this->_info_for_module( $m, $mobject ) }
}

sub calculate_info {
  my $this = shift;
  $this->_get_hints;
  my $info = $this->_get_info_object( $this->{FILE} );

  eval {
    my @used = $info->modules_used;
    push @used, @{$this->{EXTRA_MODULES}}
      if $this->{EXTRA_MODULES};

    foreach my $m ( @used ) { $this->_info_for_module
                                ( $m, $this->{FILES}->{MAIN} ) }
  };
  if( $@ ) {
    warn $@;
    return 0;
  }

  return 1;
}

sub get_files {
  my $this = shift;

  return unless exists $this->{FILES};

  return { main => $this->{FILES}->{MAIN},
           modules => [ values %{$this->{FILES}->{MODULES}} ],
           autoload => [ map { @$_ } values %{$this->{FILES}->{AUTOLOAD}} ],
           shared => [ map { @$_ } values %{$this->{FILES}->{SHARED}} ] };
}

1;

__DATA__

=head1 NAME

App::Packer::Frontend::ModuleInfo - an App::Packer::Frontend implementation

=head1 DESCRIPTION

This C<App::Packer> frontend is based upon C<Module::Info>. C<Module::Info>
is rather good at getting information from modules, but there are situatons
when it needs some hints in order to wok correctly:

=over 4

=item * prerequisites

Some modules (for example C<Tk::Entry>) require some other module
(C<Tk> in this example) to be loaded in order to compile correctly.

=item * informations

Some modules use hard to detect techniques, for example they require
other modules dynamically (i.e. require "$foo.pm"), or use dynamic loading
through non-standard modules.

=back

For this reason <App::Packer::Frontend::ModuleInfo> uses an hints file.
An hints file looks like this:

  [prerequisites]
  tk=<<EOT
  ^Tk::
  Tk
  EOT

  [skip]
  foo=<<EOT
  Foo
  Foo::Bar
  EOT
  xyz=<<EOT
  Xyz::Dummy
  EOT

  [Module::Name]
  modules_used=<<EOT
  My::Module
  Your::Module
  EOT
  uses_dynamic_loading=1

The first section lists module prerequisites: each entry has the form:

  name=<<EOT
  pattern
  prereq1
  prereq2
  EOT

Where the entry name is arbitrary.

The second section lists modules to be skipped. The entry name is
arbitrary.

=cut

# local variables:
# mode: cperl
# end:
