#ifndef __MY_LOADER_PRIV_H
#define __MY_LOADER_PRIV_H

/* need to include perl.h, first */
int do_init_perl();
SV* do_get_glob( const char* file );
int do_eval( const char* string );

#endif /* __MY_LOADER_PRIV_H */
