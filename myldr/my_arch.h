#ifndef __MY_ARCH_H
#define __MY_ARCH_H

/* for size_t */
#include <stddef.h>

/* #define MY_ARCH_EOF -1 */
typedef struct _my_arch_fh my_arch_fh;

int my_arch_init( const char* fs_file_name );
void my_arch_cleanup();
my_arch_fh* my_arch_open( const char* file_name );
int my_arch_close( my_arch_fh* fh );
int my_arch_read( my_arch_fh* fh, void* buffer, size_t count );
long my_arch_seek( my_arch_fh* fh, long offset, int whence );

#endif /* __MY_ARCH_H */
