package My_Loader;

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
