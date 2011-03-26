
# We build a colelction of cpp function factories here that'll help reduce
# boilerplate and pointer mistakes when wrapping libgit2 functions. 

@baseargs =  ( [0,1], [0,2], [0,3], [1,0], [1,1], [1,2] ) ;

# Escape all lines in a #define after removing // comments
sub slashn {
	my ($_) = @_;  chomp;
	s/\/\/[^\n]*\n/\n/g;
	s/\n/ \\\n/g;
	return $_ .= "\n\n";
}

sub set_wrap_args {
	return unless @_;
	($ptr_cnt,$val_cnt) = @_;
	$argdsc = ($ptr_cnt ? "_ptr$ptr_cnt" : "") . ($val_cnt ? "_val$val_cnt" : "");
	$def_args = join( ",",
		(map { "TYPE$_"; } (1..$ptr_cnt)),
		(map { "CONVERSION$_"; } (1..$val_cnt))  );
	$fun_args = join( ",",
		(map { "value p$_"; } (1..$ptr_cnt)),
		(map { "value v$_"; } (1..$val_cnt))  );
	$params = join( ",", (map { "p$_"; } (1..$ptr_cnt)), (map { "v$_"; } (1..$val_cnt)) );
	$paramc = $ptr_cnt + $val_cnt;
	die "CAMLparam$paramc does not exist!" if ($paramc > 5);
	$lines = join( ",\n",
		(map { "\t\t*(TYPE$_ **)Data_custom_val(p$_)" } (1..$ptr_cnt)),
		(map { "\t\tCONVERSION$_(v$_)" } (1..$val_cnt))  );
}  # eww, global variables!  ;)

sub wrap_retunit {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_retunit$argdsc(FUNCTION,$def_args)
CAMLprim value ocaml_##FUNCTION($fun_args) {
	CAMLparam$paramc($params);
	FUNCTION(  
$lines
	);
	CAMLreturn(Val_unit);
}
__EoC__
}

wrap_retunit(1,0); # only close and free?

sub wrap_retunit_exn {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_retunit_exn$argdsc(FUNCTION,ERROR,EXN,$def_args)
CAMLprim value ocaml_##FUNCTION($fun_args) {
	CAMLparam$paramc($params);
	unless_caml_##EXN(
	FUNCTION( 
$lines
	), ERROR ); 
	CAMLreturn(Val_unit);
}
__EoC__
}

wrap_retunit_exn(1,0); # only writing?


sub wrap_retval {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_retval$argdsc(FUNCTION,RETURN_CONVERSION,$def_args)
CAMLprim value ocaml_##FUNCTION($fun_args) {
	CAMLparam$paramc($params);
	CAMLreturn( RETURN_CONVERSION( FUNCTION(  
$lines
	) ) ); 
}
__EoC__
}

sub wrap_retptr {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_retptr$argdsc(FUNCTION,NEWTYPE,ERROR,$def_args)
CAMLprim value ocaml_##FUNCTION($fun_args) {
	CAMLparam$paramc($params);
	CAMLlocal1(r);
	r = caml_alloc_git_ptr(NEWTYPE);
	*(NEWTYPE **)Data_custom_val(r) =
	FUNCTION( 
$lines
	);
	unless_caml_invalid_argument(*(NEWTYPE **)Data_custom_val(r) != NULL, ERROR);
	CAMLreturn(r);
}
__EoC__
}
# We shouldn't actually need the error checking in wrap_retptr, given the
# specific routines it wraps, but who knows.  Ergo, all are invalid_argument.


sub wrap_setptr {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_setptr$argdsc(FUNCTION,NEWTYPE,ERROR,EXN,$def_args)
CAMLprim value ocaml_##FUNCTION($fun_args) {
	CAMLparam$paramc($params);
	CAMLlocal1(r);
	r = caml_alloc_git_ptr(NEWTYPE);
	unless_caml_##EXN(
	FUNCTION( (NEWTYPE **)Data_custom_val(r),
$lines
	), ERROR );
	CAMLreturn(r);
}
__EoC__
} # We support both invalid_argument and failwith





map { wrap_retval(@$_); } @baseargs;

map { wrap_retptr(@$_); } @baseargs;

map { wrap_setptr(@$_); } @baseargs;
wrap_setptr(0,3);
wrap_setptr(0,4);

