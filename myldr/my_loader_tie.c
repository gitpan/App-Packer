#define PERL_NO_GET_CONTEXT
#ifdef __WIN32__
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#if PERL_VERSION <= 6

#include <errno.h>

/* #include "my_loader.h" */
#include "my_loader_priv.h"
#include "my_arch.h"
#include "my_loader_tie_pl.c"

XS(XS_My_Loader__hook);
XS(XS_My_Loader__Tie__READLINE);
XS(XS_My_Loader__Tie__DESTROY);
XS(XS_My_Loader__Tie__TIEHANDLE);

int do_init_perl()
{
    dTHX;

    char* file = __FILE__;

    if( !do_eval( load_me ) )
        return 0;

    newXS( "My_Loader::hook", XS_My_Loader__hook, file );
    newXS( "My_Loader::Tie::TIEHANDLE", XS_My_Loader__Tie__TIEHANDLE, file );
    newXS( "My_Loader::Tie::DESTROY", XS_My_Loader__Tie__DESTROY, file );
    newXS( "My_Loader::Tie::READLINE", XS_My_Loader__Tie__READLINE, file );

    return 1;
}

/* -------------------------------------------------------------------------
 * XS
 * ------------------------------------------------------------------------- */

static SV* my_call_new( SV* sv )
{
    dTHX;
    dSP;
    int count;

    PUSHMARK(SP);
    XPUSHs( sv_2mortal( newSVpv( "My_Loader", 0 ) ) );
    XPUSHs( sv );
    PUTBACK;

    count = call_pv( "My_Loader::new", G_SCALAR );
    if( count != 1 ) croak( "BAD!" );

    SPAGAIN;
    return POPs;
}

SV* do_get_glob( const char* file )
{
    dTHX;
    SV* ret;

    {
        my_arch_fh* fh = my_arch_open( file );
        if( !fh )
            croak( "File not found: %s", file );
        ret = sv_2mortal( newSViv( PTR2IV(fh) ) );
    }

    return my_call_new( ret );
}

XS(XS_My_Loader__hook)
{
    dXSARGS;
    const char* file = SvPV_nolen( ST(1) );
    SV* ret = do_get_glob( file );

    SPAGAIN;
    ST(0) = ret;
    ST(1) = sv_2mortal( newRV((SV*)get_cv("My_Loader::Filter",0)) );
    ST(2) = ret;
    XSRETURN(3);
}

XS(XS_My_Loader__Tie__TIEHANDLE)
{
    dXSARGS;
    const char* package = "My_Loader::Tie";
    IV i_ptr = SvIV( ST(1) );
    my_arch_fh* fh = INT2PTR(my_arch_fh*,i_ptr);

    ST(0) = sv_newmortal();
    sv_setref_iv( ST(0), package, PTR2IV(fh));
    XSRETURN(1);
}

XS(XS_My_Loader__Tie__DESTROY)
{
    dXSARGS;
    IV i_fh = SvIV(SvRV(ST(0)));
    my_arch_fh* fh = INT2PTR(my_arch_fh*,i_fh);

    my_arch_close( fh );
}

#define skip_cr 0
#define return_all 0

XS(XS_My_Loader__Tie__READLINE)
{
    dXSARGS;
    IV i_fh = SvIV(SvRV(ST(0)));
    my_arch_fh* fh = INT2PTR(my_arch_fh*,i_fh);
    SV* ret = 0;
    char buffer[1024];
/*    long curr_off = my_arch_seek( fh, 0, SEEK_CUR ); */
    long count;

#if !return_all
    do
    {
        count = my_arch_read( fh, buffer, sizeof(buffer) - 1 );
        buffer[count] = 0;

        if( count == 0 )
        {
            if( !ret )
                ret = &PL_sv_undef;
            break;
        }
        else
        {
            long read = count;
            const char* nl = strchr( buffer, '\012' );

            if( !ret )
                ret = newSVpv( "", 0 );

            if( nl )
            {
                long len = nl - buffer + 1;
                /* check for CR/LF, and discard CR */
                if( skip_cr && nl != buffer && nl[-1] == '\015' )
                {
                    sv_catpvn( ret, buffer, len - 2 );
                    sv_catpvn( ret, "\012", 1 );
                }
                else
                {
                    STRLEN ret_len;
                    const char* ret_pv = SvPV( ret, ret_len );

                    if( skip_cr &&
                        ret_len != 0 && ret_pv[ret_len - 1] == '\015' )
                    {
                        SvCUR_set( ret, ret_len - 1 );
                        sv_catpvn( ret, "\012", 1 );
                    }
                    else
                    {
                        sv_catpvn( ret, buffer, len );
                    }
                }

                my_arch_seek( fh, len - read, SEEK_CUR );
                break;
            }
            else
            {
                sv_catpvn( ret, buffer, read );
            }
        }
    } while( 1 );
#else
    count = my_arch_read( fh, buffer, sizeof(buffer) - 1 );
    buffer[count] = 0;

    if( count == 0 )
        ret = &PL_sv_undef;
    else
        ret = newSVpvn( buffer, count );
#endif

    ST(0) = sv_2mortal( ret );
    XSRETURN( 1 );
}

#endif /* perl 5.6 */
