package DynaLoader;

sub dl_load_flags { 0x0 }

# cut'n' paste from DynaLoader
sub bootstrap_inherit {
    my $module = $_[0];
    local *isa = *{"$module\::ISA"};
    local @isa = (@isa, 'DynaLoader');
    # Cannot goto due to delocalization.  Will report errors on a wrong line?
    bootstrap(@_);
}

my $count = 0;

sub croak { die @_ }

my $sep = $^O eq 'MSWin32' ? '\\' : '/';
my $dlext = $^O eq 'MSWin32' ? 'dll' : 'so';

my %booted;

# does not handle .bs files
sub bootstrap {
  boot_DynaLoader('DynaLoader') if defined(&boot_DynaLoader) &&
                                  !defined(&dl_error);
  my $module = $_[0];
  return if $booted{$module};
  my @modparts = split(/::/,$module);
  my $tmp = $ENV{TEMP} || $ENV{TMP} || '/tmp';
  die "Can't find temporary directory '$tmp'" unless -d $tmp;
  my $file = "${tmp}${sep}p2e_${$}_${count}.dll"; ++$count;
  my $path = join '/', 'auto', @modparts, $modparts[-1]; $path .= ".$dlext";
  my $bootname = "boot_$module"; $bootname =~ s/\W/_/g;
  @dl_require_symbols = ($bootname);
  my $fh = My_Loader::get_file( $path ); # will croak
  open OUT, "> $file" or die "open '$modfname': $!";
  My_Loader::cleanup_file( $file );
  binmode OUT;
  while( <$fh> ) { print OUT $_; $_ = undef }
  close OUT;
  my $boot_symbol_ref;
  my $libref = dl_load_file($file, $module->dl_load_flags) or
    croak("Can't load '$file' for module $module: ".dl_error());
  push(@dl_librefs,$libref);  # record loaded object

  $boot_symbol_ref = dl_find_symbol($libref, $bootname) or
    croak("Can't find '$bootname' symbol in $file\n");

  push(@dl_modules, $module); # record loaded module

 boot:
  my $xs = dl_install_xsub("${module}::bootstrap", $boot_symbol_ref, $file);
  $booted{$module} = 1;

  # See comment block above
  &$xs(@args);
}

# required by Win32::GUI, sigh :-(
sub dl_find_symbol_anywhere
{
    my $sym = shift;
    my $libref;
    foreach $libref (@dl_librefs) {
	my $symref = dl_find_symbol($libref,$sym);
	return $symref if $symref;
    }
    return undef;
}

package XSLoader;

sub load {
  DynaLoader::bootstrap_inherit(@_);
}

$INC{'XSLoader.pm'} = 'internal';
$INC{'DynaLoader.pm'} = 'internal';

1;

# local variables:
# mode: cperl
# end:
