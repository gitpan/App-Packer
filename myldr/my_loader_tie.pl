package My_Loader;

sub my_require(*) {
  my $file = shift;
  # version
  if( $file =~ m/^\d+(?:\.\d+)?$/ ) { return $file <= $] }
  # fix for Debian perl
  if( $file =~ s{::}{/}g )
    { $file .= '.pm' }
  elsif( $file !~ m/\.\w+$/ )
    { $file .= '.pm' }
  # end fix
  return 1 if $INC{$file};
  my $stripped = $file;
  $stripped =~ s{^/loader/0x[0123456789abcdefABCDEF]+/}{};
  # require is always in scalar context before 5.9
  my $result = eval { CORE::require $stripped };
  delete $INC{$file} if $@ || !$result;
  if( $@ ) {
    if( !ref( $@ ) && $@ =~ m/^Can't locate \Q$stripped\E at/ ) {
      my( $err, $line ); ( undef, $err, $line ) = caller;
      $@ = "Can't locate $file at $err line $line\n";
    }
    die $@;
  }
  die "$file did not return a true value" unless $result;
  return $result;
};

*CORE::GLOBAL::require = \&my_require;

# straight from Symbol.pm
my $genseq;
my $genpkg = 'My_Loader::';
sub gensym () {
    my $name = "GEN" . $genseq++;
    my $ref = \*{$genpkg . $name};
    delete $$genpkg{$name};
    $ref;
}

sub new {
  shift;
  my $this = gensym();

  tie *$this, 'My_Loader::Tie', shift;

  return $this;
}

sub Filter {
  my $fh = $_[1];
  my $str = <$fh> || '';
  $_ .= $str;
  return defined( $_ ) && length( $_ );
}

1;
