#include "my_arch.h"
#include "zlib.h"
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>

#define MAGIC1 0xbadf00d
#define MAGIC2 0xdeadbeef
#define READ_BUFFER_SIZE 512

struct _my_arch_fh
{
    struct _my_arch_fh* next;
    FILE* stdio_fh;
    size_t start_offset;
    size_t length;
    size_t curr_offset; /* offset from start_offset */
    char buffer[READ_BUFFER_SIZE];
    size_t buffer_offset;
    z_streamp zlib_stream;
};

struct _my_arch_file
{
    struct _my_arch_file* next;
    const char* name;
    size_t start_offset;
    size_t length;
};
typedef struct _my_arch_file my_arch_file;

/* XXX threads */
static my_arch_fh* descriptors = NULL;
static my_arch_file* files = NULL;
static const char* exe_name = NULL;
static const char* file_data = NULL;

static int rlong( long* ptr, FILE* fh )
{
    return fread( ptr, sizeof(long), 1, fh ) == 1;
}

#define FAIL() \
    { \
        fclose( fh ); \
        my_arch_cleanup(); \
 \
        return 0; \
    }

int my_arch_init( const char* fs_file_name )
{
    FILE* fh;
    long ofs, magic;

    exe_name = strdup( fs_file_name );
    if( !exe_name ) return 0;
    fh = fopen( exe_name, "rb" );
    if( !fh ) return 0;

    /* read first magic number and offset */
    if( fseek( fh, -8, SEEK_END ) == 0 &&
        rlong( &magic, fh ) &&
        rlong( &ofs, fh ) &&
        magic == MAGIC1 )
    {
        long size, count, i;

        /* read second magic number */
        if( fseek( fh, ofs, SEEK_SET ) == 0 &&
            rlong( &magic, fh ) &&
            magic == MAGIC2 )
        {
            const char* ptr;
            char* tmp;

            /* read directory size and number of entries */
            if( !rlong( &size, fh ) ||
                !rlong( &count, fh ) )
                FAIL();

            /* read the whole directory as a single block */
            ptr = file_data = tmp = (char*)malloc( size );
            if( !ptr ||
                fread( tmp, sizeof(char), size, fh ) != size )
                FAIL();

            fclose( fh );

            /* scan the directory and construct the _file structs
             * note that the ->name member points into the
             * data allocated for the directory
             */
            for( i = 0; i < count; ++i )
            {
                size_t len = strlen( ptr ) + 1; /* trailing 0! */
                size_t padded = len + ( len % 4 ? 4 - len % 4 : 0 );
                /* pointer arithmetic games: skip to the endo of the string */
                long* ptr2 = (long*)( ptr + padded );
                /* read file offset and length */
                long offset = *ptr2++,
                     length = *ptr2++;
                my_arch_file* file =
                    (my_arch_file*)malloc( sizeof(my_arch_file) );

                file->next = files;
                files = file;

                file->name = ptr;
                file->start_offset = offset;
                file->length = length;

                ptr = (const char*)ptr2;
            }
        }
        else
            FAIL();
    }
    else
        FAIL();

    return 1;
}

#undef FAIL

void my_arch_cleanup()
{
    free( (char*)file_data );
    while( descriptors )
        my_arch_close( descriptors );
    free( (char*)exe_name );

    {
        my_arch_file* file = files;
        while( file != NULL ) {
            my_arch_file* next = file->next;
            free( file );
            file = next;
        }
    }
}

int my_arch_close( my_arch_fh* fh )
{
    my_arch_fh* cur;
    for( cur = descriptors; cur != NULL && cur->next != fh; cur = cur->next )
        ;

    fclose( fh->stdio_fh );
    inflateEnd( fh->zlib_stream );
    if( !cur )
    {
        if( descriptors == fh )
            descriptors = fh->next;
        else
            abort();
    }
    else
        cur->next = fh->next;
    free( fh );

    return 1;
}

#define FAIL() \
    { \
        fclose( sfh ); \
 \
        return 0; \
    }

my_arch_fh* my_arch_open( const char* file_name )
{
    my_arch_file* cur;
    my_arch_fh* fh;
    FILE* sfh;
    int zerr;

    for( cur = files; cur != NULL; cur = cur->next )
    {
        if( strcmp( cur->name, file_name ) == 0 )
            break;
    }

    if( !cur ) return NULL;
    sfh = fopen( exe_name, "rb" );
    if( !sfh ) return NULL;

    if( fseek( sfh, cur->start_offset, SEEK_SET ) != 0 )
        FAIL();
    fh = (my_arch_fh*)malloc( sizeof(my_arch_fh) );
    if( !fh )
        FAIL();

    fh->stdio_fh = sfh;
    fh->start_offset = cur->start_offset;
    fh->length = cur->length;
    fh->curr_offset = 0;
    fh->buffer_offset = 0;

    fh->zlib_stream = (z_streamp)malloc( sizeof(z_stream) );
    fh->zlib_stream->next_in = fh->buffer + READ_BUFFER_SIZE;
    fh->zlib_stream->avail_in = 0;
    fh->zlib_stream->zalloc = Z_NULL;
    fh->zlib_stream->zfree = Z_NULL;
    fh->zlib_stream->opaque = Z_NULL;
    zerr = inflateInit( fh->zlib_stream );
    if( zerr != Z_OK )
        my_arch_close( fh );

    fh->next = descriptors;
    descriptors = fh;

    return fh;
}

#undef FAIL

int do_read( my_arch_fh* fh, char* buffer, size_t count )
{
    if( count > fh->length - fh->curr_offset )
        count = fh->length - fh->curr_offset;
    if( count == 0 ) return 0;
    count = fread( buffer, 1, count, fh->stdio_fh );
    fh->curr_offset += count;

    return count;
}

int my_arch_read( my_arch_fh* fh, void* buffer, size_t count )
{
    z_streamp zs = fh->zlib_stream;

    zs->next_out = buffer;
    zs->avail_out = count;

    while( zs->avail_out )
    {
        int ret = inflate( zs, 0 );

        if( ret == Z_STREAM_END )
            break;
        else if( ret == Z_STREAM_ERROR )
            return -1;

        /* read more input */
        if( zs->avail_in == 0 )
        {
            if( zs->next_in == fh->buffer + READ_BUFFER_SIZE )
            {
                int count = do_read( fh, fh->buffer, READ_BUFFER_SIZE );

                /* eof or error */
                if( count <= 0 )
                    break;

                zs->avail_in = count;
                zs->next_in = fh->buffer;
            }
            else
                /* eof */
                break;
        }
    }

    return count - zs->avail_out;
}

long my_arch_seek( my_arch_fh* fh, long offset, int whence )
{
    return -1;
}
