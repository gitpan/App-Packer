package App::Packer::Backend::DemoPack;

require 5.006; # for l! in pack

use strict;
use vars '$VERSION';
use Config;
use File::Copy qw(copy);
use File::Spec::Functions qw(catfile catdir);

$VERSION = '0.08';

sub _search_exe {
  my $name = shift;

  # search for the loader in blib, then system directories
  my $blib = catdir( qw(blib arch) );
  my @dirs = ( $Config{installarchlib}, $Config{installsitearch} );

  foreach my $d ( $blib, @dirs ) {
    my $f = catfile( $d, 'auto', split( '::', __PACKAGE__ ),
                     "$name$Config{_exe}" );
    return $f if -f $f;
  }

  return;
}

# the loader
my $exe_file = _search_exe( 'embed' );
my $exe_file_z = _search_exe( 'embed_z' );
my $compress_zlib = eval { require Compress::Zlib; };

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

  $this->{COMPRESS} = $exe_file_z && $compress_zlib ? 6 : 0;

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
  my $this = shift;
  my $files = shift;
  my @skip = grep { $_->{store_as} =~ m/DynaLoader\.pm|XSLoader\.pm$/ }
    @$files;
  my @remain = grep { $_->{store_as} !~ m/DynaLoader\.pm|XSLoader\.pm$/ }
    @$files;

  while( @remain && @skip ) {
    my $skip = pop @skip;
    print "Skipping: " . $skip->{store_as} . "\n"
      if $this->_verbose >= 2;

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

  _skip_unused( $this, $this->{FILES}->{SIMPLE} );

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

my %subst_map = ( $Config{privlib}  => '$LIB',
                  $Config{archlib}  => '$ARCH',
                  $Config{sitelib}  => '$SITE',
                  $Config{sitearch} => '$SITEARCH',
                );
my $subst_pat = join '|', map { $_ = "\Q$_\E" } sort keys %subst_map;

sub _store_file($$$$$$$) {
  my( $this, $file, $as, $data, $offset, $compress, $fh ) = @_;
  my $len = -s $file;
  my $deflated = '';

  if( $compress ) {
    local $/;
    local *IN;

    open IN, "< $file" or die "Unable to open '$file': $!";
    binmode IN;
    my $d = pack "Z*", Compress::Zlib::compress( <IN> );
    close IN;
    $deflated = "\tdeflated: " . int( length( $d ) / $len * 100 ) . "%";
    print $fh $d;
    $len = length( $d );
  } else {
    copy( $file, $fh );
  }

  if( $this->_verbose >= 2 ) {
    ( my $f = $file ) =~ s/^($subst_pat)/$subst_map{$1}/o;

    print "Storing: $f => $as\tlength: $len$deflated\n";
  }

  ( $data, $offset ) = _do_append( $as, $data, $offset, $len );

  return ( $data, $offset );
}

sub _store_scalar($$$$$$$) {
  my( $this, $scalar, $as, $data, $offset, $compress, $fh ) = @_;
  if( $compress ) {
    $scalar = pack "Z*", Compress::Zlib::compress( $scalar );
    print $fh $scalar;
  } else {
    $scalar = pack "Z*", $scalar;
    print $fh $scalar;
  }

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
  my $compress = $this->{COMPRESS};
  my $exe = $compress ? $exe_file_z : $exe_file;
  local *OUT;

  open OUT, "> $file_name" or die "open '$file_name': $!";
  binmode OUT;

  print "Writing '$file_name'\n"
    if $this->_verbose >= 1;

  die "unable to find loader" unless defined $exe && -f $exe;

  copy( $exe, \*OUT );

  my $offset = -s $exe;
  my $data = '';
  my $metadata = '';
  my $count = 0;

  # add main file to metadata
  $metadata  = "Main=" . $this->{FILES}->{MAIN}->{store_as} . "\n";
  $metadata .= "Warn=1\n" if _has_w( $this->{FILES}->{MAIN}->{file} );

  ( $data, $offset ) =
    _store_file( $this, $this->{FILES}->{MAIN}->{file},
                 $this->{FILES}->{MAIN}->{store_as},
                 $data, $offset, $compress, \*OUT );
  ++$count;

  foreach my $f ( @{$this->{FILES}->{SIMPLE}} ) {
    ( $data, $offset ) = 
      _store_file( $this, $f->{file}, $f->{store_as},
                   $data, $offset, $compress, \*OUT );
    ++$count;
  }

  ( $data, $offset ) =
    _store_scalar( $this, $metadata, 'My_Loader_Metadata',
                   $data, $offset, $compress, \*OUT );
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

sub set_options {
  my $this = shift;
  my %args = @_;

  $this->{VERBOSE} = $args{verbose} || 0;
  if( $args{command_line} ) {
    foreach my $a ( @{$args{command_line}} ) {
      if( $a eq 'no-compress' ) {
        $this->{COMPRESS} = 0;
      }
    }
  }
}

sub _verbose { $_[0]->{VERBOSE} }

1;

__DATA__

# local variables:
# mode: cperl
# end:
