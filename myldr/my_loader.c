#define PERL_NO_GET_CONTEXT
#ifdef __WIN32__
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#undef free
#undef malloc

#include "my_Dyna_pm.c"
#include "my_arch.h"
#include "my_loader.h"
#include "my_loader_priv.h"
#include "xyz.h"

/* -------------------------------------------------------------------------
 * parse metadata file, return the value corresponding to the given name
 * ------------------------------------------------------------------------- */

static const char metadata_file[] = "My_Loader_Metadata";

int my_loader_get_value( const char* name, char* value, size_t maxsize )
{
    char buffer[1024];
    my_arch_fh* fh = my_arch_open( metadata_file );
    size_t count, len = strlen( name );
    const char* nmstart = buffer, *nmend = NULL;

    if( !fh ) return 0;
    count = my_arch_read( fh, buffer, sizeof(buffer) );
    buffer[count] = 0;

    for(;;)
    {
        nmstart = strstr( nmstart, name );
        if( !nmstart )
            return 0;
        else if( nmstart[len] == '=' &&
            ( nmstart == buffer || nmstart[-1] == '\012' ) )
            break;
        nmstart += len;
    }

    nmstart += len + 1;
    nmend = strchr( nmstart, '\012' );
    len = nmend - nmstart;
    if( !nmend || len > maxsize ) return 0;
    memcpy( value, nmstart, len );
    value[len] = 0;

    return 1;
}

/* ------------------------------------------------------------------------- *
 * eval string, return true on success, false on error
 * ------------------------------------------------------------------------- */

int do_eval( const char* string )
{
    dTHX;

    SV* ret = eval_pv( string, 0 );
    if( !SvOK( ret ) && SvOK( ERRSV ) )
        return 0;
    return 1;
}

/* -------------------------------------------------------------------------
 * Implement loader interface
 * ------------------------------------------------------------------------- */

XS(XS_My_Loader__get_file);
XS(XS_My_Loader__cleanup_file);

/* XXX threads */
#define TEMP_FILES_COUNT 1000
static char* gs_temp_files[TEMP_FILES_COUNT];
static int gs_temp_files_count = 0;
#ifdef WIN32
static HMODULE* gs_dll_handles = NULL;
#endif

/* XXX threads? */
static char script_name[100];

int my_loader_init()
{
    memset( gs_temp_files, 0, sizeof(gs_temp_files) );
    return 1;
}

int my_loader_init_perl()
{
    dTHX;

    char* file = __FILE__;
    int done = 0;

    {
#ifdef WIN32
        /* XXX buffer size */
        char buffer[1024];
        /* XXX check ret val */
        GetModuleFileName( GetModuleHandle( NULL ), buffer, 1024 );

        if( !my_arch_init( buffer ) )
            return 0;

        done = 1;
#elif defined(HAS_READLINK)
        SV* path = eval_pv( "( -l '/proc/self/exe' ) ?"
                            "    readlink '/proc/self/exe' :"
                            "    undef;", 0 );
        if( SvOK( path ) )
        {
            if( my_arch_init( SvPV_nolen( path ) ) )
                done = 1;
            SvREFCNT_dec( path );
        }
#endif

        if( !done )
        {
            SV* caret_x = get_sv( "\030", 0 );

            if( my_arch_init( SvPV_nolen( caret_x ) ) )
                done = 1;
        }

        if( !done )
        {
            SV* path = eval_pv
                ( "return $0 if -f $0;"
                  "foreach ( split /\\Q" PATH_SEP "\\E/, $ENV{PATH} ) {"
                  "    my $p = qq{$_/$0};"
                  "    return $p if -f $p;"
                  "}", 1 );

            if( SvOK( path ) )
            {
                if( my_arch_init( SvPV_nolen( path ) ) )
                    done = 1;
                SvREFCNT_dec( path );
            }
        }
    }

    if( !done )
        return 0;

    /* get -w switch */
    {
        char value[2];
        int ret = my_loader_get_value( "Warn", value, 1 );

        if( ret && value[0] == '1' )
        {
            SV* w = get_sv( "\027", 1 );
            sv_setiv( w, 1 );
            SvSETMAGIC( w );
        }
    }

    if( !do_eval( load_me_2 ) )
        return 0;

    {
        SV* tmp;

        tmp = get_sv( "DynaLoader::VERSION", 1 );
        sv_setpv( tmp, DYNALOADER_VERSION );

        tmp = get_sv( "XSLoader::VERSION", 1 );
        sv_setpv( tmp, XSLOADER_VERSION );
    }

    newXS( "My_Loader::get_file", XS_My_Loader__get_file, file );
    newXS( "My_Loader::cleanup_file", XS_My_Loader__cleanup_file, file );

    if( !do_init_perl() )
        return 0;

    return 1;
}

SV* my_loader_get_inc_hook()
{
    dTHX;

    return sv_2mortal( newRV( (SV*)get_cv( "My_Loader::hook", 0 ) ) );
}

const char* my_loader_get_script_name()
{
    int ret = my_loader_get_value( "Main", script_name, 99 );

    return ret ? script_name : NULL;
}

void my_loader_cleanup_perl()
{
/* win32 does not have dl_unload_file */
#ifdef WIN32
    dTHX;
    AV* av = get_av( "DynaLoader::dl_librefs", 1 );
    int len = av_len( av ) + 1;
    int i;

    gs_dll_handles = (HMODULE*)malloc( ( len + 1 ) * sizeof(HMODULE) );
    gs_dll_handles[len] = NULL;

    for( i = len - 1; i >= 0; --i )
    {
        SV* sv = *av_fetch( av, i, 0 );
        HMODULE mod = (HMODULE)SvIV( sv );

        gs_dll_handles[i] = mod;
    }
#endif
}

void my_loader_cleanup()
{
    int i;
    dTHX;

#ifdef WIN32
    if( gs_dll_handles )
    {
        for( i = 0; gs_dll_handles[i] != NULL; ++i )
        {
            while( FreeLibrary( gs_dll_handles[i] ) );
#if 0
                fprintf( stderr, "Error in FreeLibrary\n" );
#endif
        }

        free( gs_dll_handles );
    }
#endif
    for( i = 0; i < gs_temp_files_count; ++i )
    {
        int ret = remove( gs_temp_files[i] );
#if 0
        if( ret != 0 )
            fprintf( stderr, "remove '%s': %s", gs_temp_files[i],
                     strerror( errno ) );
#endif
        free( gs_temp_files[i] );
    }
}

/* -------------------------------------------------------------------------
 * XS
 * ------------------------------------------------------------------------- */

XS(XS_My_Loader__get_file)
{
    dXSARGS;
    const char* file = SvPV_nolen( ST(0) );
    SV* ret = do_get_glob( file );

    SPAGAIN;
    ST(0) = ret;
    XSRETURN(1);
}

XS(XS_My_Loader__cleanup_file)
{
    dXSARGS;
    const char* file = SvPV_nolen( ST(0) );

    if( gs_temp_files_count == TEMP_FILES_COUNT )
        croak( "Too many temp files!" );
    gs_temp_files[gs_temp_files_count++] = strdup( file );

    XSRETURN_EMPTY;
}
