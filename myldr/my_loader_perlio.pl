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

sub Filter {
  return defined( $_ ) && length( $_ );
}

1;
