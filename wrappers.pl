
# We build a colelction of cpp function factories here that'll help reduce
# boilerplate and pointer mistakes when wrapping libgit2 functions. 

@valargs = ( [0,1], [0,2], [0,3] );
@ptrargs =  ( [1,0], [1,1], [1,2] );
# @valargs = ( "v","vv","vvv" );
# @ptrargs =  ( "p", "pv","pvv","pvvv" );

# Escape all lines in a #define after removing // comments
sub slashn {
	my ($_) = @_;  chomp;
	s/\/\/[^\n]*\n/\n/g;
	s/\n/ \\\n/g;
	return $_ .= "\n\n";
}

sub alt_set_wrap_args {
	return unless @_;
	$argdsc = $_[0];
	$paramc = length $argdsc;
	die "CAMLparam$paramc does not exist!" if ($paramc > 5);

	sub argdsc_map(%) { my %f = @_;  map { $_ = 1+pos; &{$f{$1}}; } ($argdsc =~ /([pv])/); }
	$params = join(",", argdsc_map( p => sub{"p$_"}, v => sub{"v$_"} ));
	$defargs = join(",", argdsc_map( p => sub {"TYPE$_"}, v => sub {"CONVERSION$_"} ));
	$funargs = join(",", argdsc_map( p => sub {"value p$_"}, v => sub {"value v$_"} ));
	$lines = join(",\n", argdsc_map(
		p => { "\t\t*(TYPE$_ **)Data_custom_val(p$_)" },
		v => { "\t\tCONVERSION$_(v$_)" }
	));
}  # eww, global variables!  ;)

sub set_wrap_args {
	return unless @_;
	($ptr_cnt,$val_cnt) = @_;
	$argdsc = ($ptr_cnt ? "_ptr$ptr_cnt" : "") . ($val_cnt ? "_val$val_cnt" : "");
	$defargs = join( ",",
		(map { "TYPE$_"; } (1..$ptr_cnt)),
		(map { "CONVERSION$_"; } (1..$val_cnt))  );
	$funargs = join( ",",
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
#define wrap_retunit$argdsc(FUNCTION,$defargs)
CAMLprim value ocaml_##FUNCTION($funargs) {
	CAMLparam$paramc($params);
	FUNCTION(  
$lines
	);
	CAMLreturn(Val_unit);
}
__EoC__
}

wrap_retunit(1,0);
wrap_retunit(1,1);

sub wrap_retunit_exn {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_retunit_exn$argdsc(FUNCTION,ERROR,EXN,$defargs)
CAMLprim value ocaml_##FUNCTION($funargs) {
	CAMLparam$paramc($params);
	pass_git_exceptions(
	FUNCTION( 
$lines
	), ERROR, EXN ); 
	CAMLreturn(Val_unit);
}
__EoC__
}

map { wrap_retunit_exn(@$_); } @ptrargs;
wrap_retunit_exn(2,0);

sub wrap_retval {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_retval$argdsc(FUNCTION,RETURN_CONVERSION,$defargs)
CAMLprim value ocaml_##FUNCTION($funargs) {
	CAMLparam$paramc($params);
	CAMLreturn( RETURN_CONVERSION( FUNCTION(  
$lines
	) ) ); 
}
__EoC__
}

map { wrap_retval(@$_); } (@valargs, @ptrargs);


sub wrap_retptr {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_retptr$argdsc(FUNCTION,NEWTYPE,ERROR,$defargs)
CAMLprim value ocaml_##FUNCTION($funargs) {
	CAMLparam$paramc($params);
	CAMLlocal1(r);
	r = caml_alloc_git_ptr(NEWTYPE);
	*(NEWTYPE **)Data_custom_val(r) =
	FUNCTION( 
$lines
	);
	if( *(NEWTYPE **)Data_custom_val(r) == NULL )
		caml_invalid_argument( #ERROR " : " #FUNCTION " returned null." );
	CAMLreturn(r);
}
__EoC__
}
# Afaik, all are invalid_argument.

map { wrap_retptr(@$_); } (@valargs, @ptrargs);


sub wrap_setptr {
	set_wrap_args(@_);
	print slashn( <<__EoC__ );
#define wrap_setptr$argdsc(FUNCTION,NEWTYPE,ERROR,EXN,$defargs)
CAMLprim value ocaml_##FUNCTION($funargs) {
	CAMLparam$paramc($params);
	CAMLlocal1(r);
	r = caml_alloc_git_ptr(NEWTYPE);
	pass_git_exceptions(
	FUNCTION( (NEWTYPE **)Data_custom_val(r),
$lines
	), ERROR, EXN );
	CAMLreturn(r);
}
__EoC__
} # We support both invalid_argument and failwith

map { wrap_setptr(@$_); } (@valargs, [0,3], [0,4], @ptrargs, [1,3]);

