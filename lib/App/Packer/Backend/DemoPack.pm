package App::Packer::Backend::DemoPack;

require 5.006; # for l! in pack

use strict;
use vars '$VERSION';
use Config;
use File::Copy qw(copy);
use File::Spec::Functions qw(catfile catdir);

$VERSION = '0.04';

# the loader
my $exe_file;

{
  # search for the loader in blib, then system directories
  my $blib = catdir( qw(blib arch) );
  my @dirs = ( $Config{installarchlib}, $Config{installsitearch} );

  foreach my $d ( $blib, @dirs ) {
    my $f = catfile( $d, 'auto', split( '::', __PACKAGE__ ),
                     "embed$Config{_exe}" );
    if( -f $f ) { $exe_file = $f; last }
  }
}

# magic numbers
sub MAGIC1() { 0xbadf00d }
sub MAGIC2() { 0xdeadbeef }

# pack a 'long' value
sub _pack_long($) {
  return pack "l!", $_[0];
}

sub new {
  my $ref = shift;
  my $class = ref( $ref ) || $ref;
  my $this = bless {}, $class;

  return $this;
}

# TRUE if the argument is a file specification for
#      an existing file
# FALSE otherwise
sub _is_file_spec($) {
  my $spec = shift;

  return 0 unless ref( $spec ) eq 'HASH';
  return 0 unless defined( $spec->{file} ) and -f $spec->{file};
  return 0 unless defined $spec->{store_as};
}

# "pretty"-print an hash reference, used for debugging
sub _pp_hash($) {
  my $h = shift;

  return join ' ', map { "${_}=" . $h->{$_} } keys %$h;
}

sub _skip_unused {
  my $files = $_[0];
  my @skip = grep { $_->{store_as} =~ m/DynaLoader\.pm|XSLoader\.pm$/ }
    @$files;
  my @remain = grep { $_->{store_as} !~ m/DynaLoader\.pm|XSLoader\.pm$/ }
    @$files;

  while( @remain && @skip ) {
    my $skip = pop @skip;
#    print "Skipping: " . $skip->{store_as} . "\n";

    my $i1 = 0;
    foreach my $f ( @remain ) {
      my $i2 = 0;
      foreach my $u ( @{$f->{used_by}} ) {
        if( $u eq $skip ) {
          splice @{$f->{used_by}}, $i2, 1;
          if( !@{$f->{used_by}} ) { push @skip, splice @remain, $i1, 1 }
          last;
        }
        ++$i2;
      }
      ++$i1;
    }
  }

  @$files = @remain;
}

sub set_files {
  my $this = shift;
  my %files = @_;

  foreach my $k ( keys %files ) {
    ( $k eq 'modules' || $k eq 'autoload' || $k eq 'shared' ) && do {
      push @{$this->{FILES}->{SIMPLE}}, @{$files{$k}};

      foreach my $sp ( @{$files{$k}} ) {
        die "Invalid file specification" . _pp_hash( $sp )
          unless _is_file_spec( $sp );
      }

      next;
    };
    $k eq 'main' && do {
      $this->{FILES}->{MAIN} = $files{$k};

      die "Invalid file specification " . _pp_hash( $files{$k} )
          unless _is_file_spec( $files{$k} );
      next;
    };

    die "The file type '$k' is not supported";
  }

  _skip_unused( $this->{FILES}->{SIMPLE} );

  die "Must specify a main file"
    unless defined $this->{FILES}->{MAIN};

  return 1;
}

sub _do_append {
  my( $as, $data, $offset, $len ) = @_;

  my $str = pack "Z*", $as;
  $str .= '!' x ( length( $str ) % 4 ? 4 - length( $str ) % 4 : 0 );

  $data .= $str;
  $data .= _pack_long( $offset );
  $data .= _pack_long( $len );

  $offset += $len;

  return ( $data, $offset );
}

sub _store_file($$$$$) {
  my( $file, $as, $data, $offset, $fh ) = @_;
  my $len = -s $file;

  print "File: $file=>$as,\toffset $offset,\tlength: $len\n";
  copy( $file, $fh );

  ( $data, $offset ) = _do_append( $as, $data, $offset, $len );

  return ( $data, $offset );
}

sub _store_scalar($$$$$) {
  my( $scalar, $as, $data, $offset, $fh ) = @_;
  $scalar = pack "Z*", $scalar;
  print $fh $scalar;

  ( $data, $offset ) = _do_append( $as, $data, $offset, length( $scalar ) );

  return ( $data, $offset );
}

sub _has_w {
  my $file = shift;
  local *IN;

  open IN, "< $file" or die "open '$file': $!";
  my $fst = <IN>;
  close IN;

  return $fst =~ m/^#!\S*perl.*-w/;
}

sub write {
  my $this = shift;
  my $file_name = shift;
  local *OUT;

  open OUT, "> $file_name" or die "open '$file_name': $!";
  binmode OUT;

  die "unable to find loader" unless defined $exe_file && -f $exe_file;

  copy( $exe_file, \*OUT );

  my $offset = -s $exe_file;
  my $data = '';
  my $metadata = '';
  my $count = 0;

  # add main file to metadata
  $metadata  = "Main=" . $this->{FILES}->{MAIN}->{store_as} . "\n";
  $metadata .= "Warn=1\n" if _has_w( $this->{FILES}->{MAIN}->{file} );

  ( $data, $offset ) =
    _store_file( $this->{FILES}->{MAIN}->{file},
                 $this->{FILES}->{MAIN}->{store_as},
                 $data, $offset, \*OUT );
  ++$count;

  foreach my $f ( @{$this->{FILES}->{SIMPLE}} ) {
    ( $data, $offset ) = 
      _store_file( $f->{file}, $f->{store_as},
                   $data, $offset, \*OUT );
    ++$count;
  }

  ( $data, $offset ) =
    _store_scalar( $metadata, 'My_Loader_Metadata',
                   $data, $offset, \*OUT );
  ++$count;

  print OUT _pack_long( MAGIC2 );
  print OUT _pack_long( length( $data ) );
  print OUT _pack_long( $count );
  print OUT $data;
  print OUT _pack_long( MAGIC1 );
  print OUT _pack_long( $offset );

  close OUT;

  return 1;
}

1;

__DATA__

# local variables:
# mode: cperl
# end:
