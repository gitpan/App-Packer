#define PERL_NO_GET_CONTEXT
#ifdef __WIN32__
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#if PERL_VERSION >= 8

#include <perliol.h>
#include <errno.h>

/* #include "my_loader.h" */
#include "my_loader_priv.h"
#include "my_arch.h"
#include "my_loader_perlio_pl.c"

XS(XS_My_Loader__hook);

extern PerlIO_funcs PerlIO_my_arch;

int do_init_perl()
{
    dTHX;

    char* file = __FILE__;

    if( !do_eval( load_me ) )
        return 0;

    newXS( "My_Loader::hook", XS_My_Loader__hook, file );

    PerlIO_define_layer( aTHX_ &PerlIO_my_arch );

    return 1;
}

/* -------------------------------------------------------------------------
 * PerlIO layer
 * ------------------------------------------------------------------------- */

typedef struct
{
    struct _PerlIO base;
    my_arch_fh* fh;
} PerlIOl_my_arch;

#define my_get_fh( f ) ( PerlIOSelf( f, PerlIOl_my_arch )->fh )

static SSize_t PerlIOl_my_arch_read( pTHX_ PerlIO *f, void* vbuf,
                                     Size_t count )
{
    long rd;
    my_arch_fh* fh = my_get_fh( f );

    rd = my_arch_read( fh, vbuf, count );
    if( rd == 0 )
    {
        PerlIOBase(f)->flags |= PERLIO_F_EOF;
    }

    return rd;
}

static IV PerlIOl_my_arch_seek( pTHX_ PerlIO *f, Off_t offset, int whence )
{
    my_arch_fh* fh = my_get_fh( f );

    return my_arch_seek( fh, offset, whence );
}

static Off_t PerlIOl_my_arch_tell( pTHX_ PerlIO *f )
{
    my_arch_fh* fh = my_get_fh( f );

    return my_arch_seek( fh, 0, SEEK_CUR );
}

static IV PerlIOl_my_arch_close( pTHX_ PerlIO *f )
{
    my_arch_fh* fh = my_get_fh( f );

    PerlIOBase(f)->flags &= ~PERLIO_F_OPEN;
    my_arch_close( fh );

    return 0;
}

#undef my_get_fh

PerlIO_funcs PerlIO_my_arch = {
    sizeof(PerlIO_my_arch),
    "my_arch",
    sizeof(PerlIOl_my_arch),
    PERLIO_K_RAW,
    PerlIOBase_pushed,
    PerlIOBase_popped,
    NULL,
    PerlIOBase_binmode,
    NULL,
    NULL,
    NULL,
    PerlIOl_my_arch_read,
    NULL,
    NULL,
    PerlIOl_my_arch_seek,
    PerlIOl_my_arch_tell,
    PerlIOl_my_arch_close,
    NULL,
    NULL,
    PerlIOBase_eof,
    PerlIOBase_error,
    PerlIOBase_clearerr,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
};

static PerlIO* arch_to_PerlIO( my_arch_fh* fh )
{
    dTHX;
    PerlIO* f = PerlIO_allocate( aTHX );
    if( !f ) return NULL;

    PerlIO_apply_layers( aTHX_ f, "rb", ":my_arch" );

    if( f )
    {
        PerlIOl_my_arch* st = PerlIOSelf( f, PerlIOl_my_arch );
        st->fh = fh;
        PerlIOBase( f )->flags |= PERLIO_F_OPEN;

        return f;
    }

    return NULL;
}

#undef do_open

static SV* do_open( SV* gvref, my_arch_fh* fh )
{
    dTHX;
    GV* gv;
    IO* io;
    PerlIO* pio;

    if( !SvROK( gvref ) ) return NULL;
    gv = (GV*)SvRV( gvref );
    if( SvTYPE( gv ) != SVt_PVGV ) return NULL;

    if( GvIO( gv ) )
    {
        SvREFCNT_dec( GvIO( gv ) );
        GvIOp( gv ) = NULL;
    }

    pio = arch_to_PerlIO( fh );
    io = GvIOn( gv );
    IoIFP( io ) = IoOFP( io ) = pio;
    IoTYPE( io ) = IoTYPE_RDONLY;
    IoFLAGS( io ) = IOf_UNTAINT;

    return gvref;
}

SV* do_get_glob( const char* file )
{
    dTHX;
    dSP;
    SV* ret;
    my_arch_fh* fh = my_arch_open( file );
    I32 count;

    PUSHMARK(SP);
    PUTBACK;
    count = call_pv( "My_Loader::gensym", G_SCALAR );
    SPAGAIN;

    if( !fh || count != 1 )
        croak( "Can't locate %s", file );

    ret = do_open( POPs, fh );
    if( !ret )
    {
        my_arch_close( fh );
        croak( "Error while opening file %s", file );
    }

    return ret;
}

/* -------------------------------------------------------------------------
 * XS
 * ------------------------------------------------------------------------- */

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

#endif /* perl 5.8 */
