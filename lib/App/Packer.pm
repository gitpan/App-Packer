package App::Packer;

use strict;
use vars qw($VERSION);
use Config;

$VERSION = 0.07;

sub new {
  my $ref = shift;
  my $class = ref $ref || $ref;
  my $this = bless {}, $class;
  my %args = @_;

  # apply default values for frontend/backend
  $args{frontend} ||= 'App::Packer::Frontend::ModuleInfo';
  $args{backend} ||= 'App::Packer::Backend::DemoPack';

  # automatically require default frontend/backend
  if( $args{frontend} eq 'App::Packer::Frontend::ModuleInfo' ) {
    require App::Packer::Frontend::ModuleInfo;
  }
  if( $args{backend} eq 'App::Packer::Backend::DemoPack' ) {
    require App::Packer::Backend::DemoPack;
  }

  $this->{FRONTEND} = $args{frontend}->new;
  $this->{BACKEND} = $args{backend}->new;

  return $this;
}

sub set_file {
  my $this = shift;
  my $file = shift;

  warn( "File not found '$file'" ), return unless -f $file;

  $this->_frontend->set_file( $file );

  return 1;
}

sub write {
  my $this = shift;
  my $exe = shift;
  my $ret = 1;

  # attach exe extension
  $exe .= $Config{_exe} unless $exe =~ m/$Config{_exe}$/i;

  # write file
  $this->_frontend->calculate_info;
  my $files = $this->_frontend->get_files;
  $ret &= $files ? 1 : 0;
  $ret &= $this->_backend->set_files( %$files );
  $ret &= $this->_backend->write( $exe );

  chmod 0755, $exe if $ret;

  $ret ? return $exe : return;
}

sub set_options {
  my $this = shift;
  my %args = @_;

  if( exists $args{frontend} ) {
    $this->_frontend->set_options( %{$args{frontend}} );
  }
  if( exists $args{backend} ) {
    $this->_backend->set_options( %{$args{backend}} );
  }
}

sub _frontend { $_[0]->{FRONTEND} || die "No frontend available" }
sub _backend { $_[0]->{BACKEND} || die "No backend available" }

1;

__END__

=head1 NAME

App::Packer - pack applications in a single executable file

=head1 DESCRIPTION

App::Packer packs perl scripts and all of their dependencies inside
an executable.

=head1 RETURN VALUES

All methods return a false value on failure, unless otherwise specified.

=head1 METHODS

=head2 new

  my $packer = App::Packer->new( frontend => class,
                                 backend  => class );

Creates a new C<App::Packer> instance, using the given classes as
frontend and backend.

'frontend' defaults to C<App::Packer::Frontend::ModuleInfo>, 'backend'
to C<App::Packer::Backend::DemoPack>. You need to C<use My::Module;>
if you pass C<My::Module> as frontend or backend, I<unless> you use
the default value.

=head2 set_file

  $packer->set_file( 'path/to/file' );

Sets the file name of the script to be packed.

=head2 write

  my $file = $packer->write( 'my_executable' );

Writes the executable file; the file name is just the basename of the file:
$Config{_exe} will be appended, and the file will be made executable
(via chmod 0755).

The return value is the file name that was actually created.

=head2 set_options

  $packer->set_options( frontend => { option1 => value1,
                                      ... },
                        backend  => { option9 => value9,
                                      ... },
                       );

Sets the options for frontend and backend; see the documentation
for C<App::Packer::Frontend> and C<App::Packer::Backend> for details.

=head1 SEE ALSO

L<App::Packer::Frontend|App::Packer::Frontend>,
L<App::Packer::Backend|App::Packer::Backend>.

=head1 AUTHOR

Mattia Barbon <mbarbon@dsi.unive.it>

=cut

# local variables:
# mode: cperl
# end:
