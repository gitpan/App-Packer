#define PERL_NO_GET_CONTEXT
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

/* expletive */
#undef malloc
#undef free

#include "my_loader.h"

#ifdef WIN32
#define snprintf _snprintf
#endif

static PerlInterpreter *my_perl;

static void xs_init( pTHX );
EXTERN_C void boot_DynaLoader( pTHX_ CV* cv );

char** prepare_args( int argc, char** argv, int* my_argc )
{
    int i, count = ( argc ? argc : 1 ) + 3;
    char** my_argv = (char**) malloc( ( count + 1 ) * sizeof(char**) );

    my_argv[0] = strdup( argc ? argv[0] : "" );
    my_argv[1] = strdup( "-e" );
    my_argv[2] = strdup( "0" );
    my_argv[3] = strdup( "--" );

    for( i = 4; i < count; ++i )
    {
        my_argv[i] = strdup( argv[ i - 3 ] );
    }

    my_argv[ count + 1 ] = NULL;

    *my_argc = count;
    return my_argv;
}

void delete_args( int argc, char** argv )
{
    int i;

    for( i = 0; i < argc; ++i )
        free( argv[i] );

    free( argv );
}

int main( int argc, char **argv, char **env )
{
    int my_argc;
    char** my_argv;
    char buffer[1024];
    int init = 0, pinit = 0;

    my_argv = prepare_args( argc, argv, &my_argc );
    init = my_loader_init();
    if( init )
    {
        my_perl = perl_alloc();
        perl_construct(my_perl);
        perl_parse(my_perl, xs_init, my_argc, my_argv, (char **)NULL);

        perl_run(my_perl);

        pinit = my_loader_init_perl();
        if( pinit )
        {
            SV* inc_hook = my_loader_get_inc_hook();
            SV* errsv_save;
            int is_error = 0;

            if( inc_hook )
            {
                SV* ret;
                AV* inc = get_av( "INC", 0 );
                int size;

                av_clear( inc );

                av_push( inc, inc_hook );

                size = snprintf( buffer, sizeof(buffer),
                                 "my $x = do '%s';die $@ if !defined $x && $@;",
                                 my_loader_get_script_name() );
                if( size < 0 )
                {
                    croak( "File name too long" );
                }

                ret = eval_pv( buffer, 0 );
                is_error = !SvOK( ret ) && SvOK( ERRSV );
                if( is_error )
                {
                    errsv_save = newSViv( 0 );
                    sv_setsv( errsv_save, ERRSV );
                }
            }

            my_loader_cleanup_perl();

            if( is_error )
            {
                my_loader_cleanup();
                sv_setsv( ERRSV, errsv_save );
                if( sv_isobject( ERRSV ) )
                    croak( Nullch );
                else
                    croak( SvPV_nolen( ERRSV ) );
            }
        }

        perl_destruct(my_perl);
        perl_free(my_perl);

        my_loader_cleanup();
    }

    /* delete_args( my_argc, my_argv ); */

    return init && pinit;
}

EXTERN_C void
xs_init(pTHX)
{
    char *file = __FILE__;
    /* DynaLoader is a special case */
    newXS("DynaLoader::boot_DynaLoader", boot_DynaLoader, file);
}
