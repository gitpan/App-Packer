App::Packer packs perl scripts and all of their dependencies inside
an executable.

Copyright (c) 2002 Mattia Barbon.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

LIMITATIONS

* it requires an hacked version of Module::Info
  (available at http://wwwstud.dsi.unive.it/~mbarbon/p2e/)
* it won't cripple (a.k.a. protect) your source code (see below).
* DATA filehandle will not work with perl 5.6.x
* requires a working $^X (for example under Linux you need to
  invoke the executable using either ./my or /path/to/my)
* p2e.pl does not allow you to add/remove arbitrary files
* if the perl you compiled against uses a shared libperl.so/perl.dll
  you need to ship it with the executable
* p2e.pl is just a quick demonstrative hack
* see TODO.txt
* many, many, many more

HINTS

  Some modules (notably Tk) do some magic that Module::Info can't
understand; in order for Tk programs to pack correctly,
App::Packer uses an hints file, named
$LIB/App/Packer/Frontend/ModuleInfo/hints.ini.

  You can use the hints.ini file included in this distribution as
a model; you are kindly invited to send back any modifications you
need to do, so that they can be included in successive releases
of App::Packer.

CODE OBFUSCATION

  This module is open source, hence anyone can see the code, and
look at how packing and unpacking is implemented: this means that
adding encryption/obfuscation/whatever code to it is useless.

SPEED AND CACHING

  Some modules (notably Tk::* and Wx::*) take a very long time for their
dependencies to be analysed, hence App::Packer uses caching to speed
things up. This means that the first time you pack a Tk program,
it will take a *very* long time, while subsequent packing of programs
using Tk, will take much less time.
  A side effect of using a cache is that sometimes the cache stores
wrong results, hence you may need to clean the cache (it is a .packfile
directory in one of $ENV{HOME}, $ENV{TMP}, $ENV{TEMP}.

THANKS

to Andrea Maestrutti for testing the first releases of this module.
