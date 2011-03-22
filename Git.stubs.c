
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/custom.h>

#include <string.h>
#include <stdio.h>

#include <git2.h>

// Be aware, we explploit preprocessor substitutions involving ## and # to
// slightly reduce boilerplate and reduce the risk of cut & paste errors.
// All macros that create functions will begin define_... and use upercase
// substitution parameters


/* *** Git's error handling *** */

#define define_unless_caml(EXN) \
void unless_caml_##EXN( int r, char *s ) { \
	if (r != 0) { \
		char *buf = String_val(caml_alloc_string(256)); \
		snprintf(buf,256,"%s : %s",s,git_strerror(r)); \
		caml_##EXN(buf); \
	} \
}  // GIT_SUCCESS = 0

define_unless_caml(failwith); 
	// Failure indicates bad user input
define_unless_caml(invalid_argument);
	// Invalid argument indicates programming problem


/* *** Convert git object ids to and from hex *** */

CAMLprim value
ocaml_git_oid_from_hex( value hex ) {
   CAMLparam1(hex);
   CAMLlocal1(id);
   id = caml_alloc_string( GIT_OID_RAWSZ );
   unless_caml_failwith(
      git_oid_mkstr( (git_oid *)String_val(id),
            (const char *) String_val(hex)),
      "Git.Oid.from_hex");
   CAMLreturn(id);
}  /* git_oid_mkstr is among the worst named methods I've ever seen */

CAMLprim value
ocaml_git_oid_to_hex( value oid ) {
   CAMLparam1(oid);
   CAMLlocal1(hex);
   hex = caml_alloc_string( GIT_OID_HEXSZ );
   if( caml_string_length(oid) < GIT_OID_RAWSZ )
      caml_invalid_argument("Git.Oid.to_hex : Corrupt argument");
   git_oid_fmt( (char *)String_val(hex), (git_oid *)String_val(oid) );
   CAMLreturn(hex);
}


/* *** Time and signature operations *** */

git_time ocaml_time_to_git_time( value t ) {
	git_time r;
	r.time = Double_val(Field(t,0));
	r.offset = Int_val(Field(t,1));
	return r;
}

CAMLprim value git_time_to_ocaml_time( git_time t ) {
	CAMLparam0();
	CAMLlocal1(b);
	b = caml_alloc_small(2,0);
	Store_field(b, 0, caml_copy_double(t.time));
	Store_field(b, 1, Val_int(t.offset));
	CAMLreturn(b);
}

// All operations that take signatures apperently call git_signature_dup,
// meaning we may construct transient signatures using pointers to strings
// in ocaml records.  We must copy the strings going back the other way though.

git_signature ocaml_signture_to_git_signture_dirty( value v ) {
	git_signature g;
	g.name = String_val(Field(v,0));
	g.email = String_val(Field(v,1));
	g.when = ocaml_time_to_git_time(Field(v,3));
	return g;
} // use for git_commit_set_committer, git_commit_set_author, git_tag_set_tagger

CAMLprim value git_signture_to_ocaml_signture( const git_signature *sig ) {
	CAMLparam0();
	CAMLlocal1(b);
	b = caml_alloc(3,0);
	Store_field(b, 0, caml_copy_string(sig->name) );
	Store_field(b, 1, caml_copy_string(sig->email) );
	Store_field(b, 2, git_time_to_ocaml_time(sig->when) );
	CAMLreturn(b);
} // use for git_commit_committer and git_commit_author, git_tag_tagger


/* *** Git pointer data types macros *** */

// We may store pointers to git data structures in custom blocks, but this
// requires interacting cleanly with libgit2's existing memory managment.
// In particular, we must know whether any give data structure is reachable
// from inside another git data structure.  I believe out best strategy runs
// as follows :
// - If a git data structure was produced by another git data structure,
//   then ignore garbage collection completely, trusting git's cleanup
//   and prodicing any essential manual free commands.  (manual mode)
// - If a git data structure must be created by ocaml from scratch, then
//   we first verfy that libgit2 copies the data structure upon insertion,
//   and free them during garbage collector finilazation. (gced mode)
// - Any such data structures git does not duplicate upon insertion must
//   be switched from gced mode to manual mode upon insertion, or copied.
// Two Warnings :
// - We must verify libgit2's memory policy when adding write functionality.
// - You may not open a git repository, copy out its objects, and then
//   free it while keeping the objects.  It's called free is not close.

int custom_ptr_compare( value a, value b ) {
   CAMLparam2(a,b);
   CAMLreturn(Val_bool(
        *(void **)Data_custom_val(a) == *(void **)Data_custom_val(b) ));
}

#define define_git_ptr_type_manual(N) \
static struct custom_operations git_##N##_manual_custom_ops = { \
    identifier:  "Git " #N " manual pointer handling", \
    finalize:    custom_finalize_default, \
    compare:     &custom_ptr_compare, \
    hash:        custom_hash_default, \
    serialize:   custom_serialize_default, \
    deserialize: custom_deserialize_default \
};

#define define_git_ptr_type_gced(N) \
void custom_git_##N##_ptr_finalize (value v) { \
	CAMLparam1(v); \
	git_##N##_free( *(git_##N **)Data_custom_val(v) ); \
	CAMLreturn; \
} \
static struct custom_operations git_##N##_gced_custom_ops = { \
    identifier:  "Git " #N "GCed pointer handling", \
    finalize:    &custom_git_##N##_ptr_finalize, \
    compare:     &custom_ptr_compare, \
    hash:        custom_hash_default, \
    serialize:   custom_serialize_default, \
    deserialize: custom_deserialize_default \
};

#define caml_alloc_git_ptr(GITTYPE,MODE) \
	caml_alloc_custom( & GITTYPE##_##MODE##_custom_ops, \
		sizeof(GITTYPE *), 0, 1 )
// The GA parameters used = 0 and max = 1 are unsuitble for large
// alloctions like repositories, but that's a problem for another day.


/* *** Index operations *** */

// define_git_ptr_type_manual(index);
// define_git_ptr_type_gced(index);


/* *** Repository and object database operations *** */

; // Needed for names by caml_alloc_git_ptr's naming convention
typedef git_odb git_database;
define_git_ptr_type_manual(database);  
define_git_ptr_type_manual(repository);
// We're giving ocamls garbage collector power to free the whole repository
// because we assume the outer loop is ocaml.  If the outter loop were C
// then you'd take another appraoch.

CAMLprim value
ocaml_git_odb_exists( value db, value id ) {
   CAMLparam2(db,id);
   CAMLreturn( Val_bool(git_odb_exists(
        *(git_odb **)Data_custom_val(db),
        (git_oid *)String_val(id)
   )) );
}

CAMLprim value
ocaml_git_repository_database( value repo ) {
   CAMLparam1(repo);
   CAMLlocal1(db);
   db = caml_alloc_git_ptr(git_database,manual);
   *(git_odb **)Data_custom_val(db) =
        git_repository_database( *(git_repository **)Data_custom_val(repo) );
   CAMLreturn(db);
}

CAMLprim value
ocaml_git_repository_init( value bare, value dir ) {
   CAMLparam2(bare,dir);
   CAMLlocal1(repo);
   repo = caml_alloc_git_ptr(git_repository,manual);
   unless_caml_failwith(
      git_repository_init( (git_repository **)Data_custom_val(repo),
            String_val(dir), Bool_val(bare) ),
      "Git.Repository._init");
   CAMLreturn(repo);
}

CAMLprim value
ocaml_git_repository_open1( value dir ) {
   CAMLparam1(dir);
   CAMLlocal1(repo);
   repo = caml_alloc_git_ptr(git_repository,manual);
   unless_caml_failwith(
      git_repository_open( (git_repository **)Data_custom_val(repo),
            String_val(dir) ),
      "Git.Repository.open1");
   CAMLreturn(repo);
}

CAMLprim value
ocaml_git_repository_free( value repo ) {
   CAMLparam1(repo);
   git_repository_free( *(git_repository **)Data_custom_val(repo) );
   CAMLreturn(Val_unit);
}  // Warning : git_repository_close exists only as an extern in repository.h


/* indexs are yet currently supported */
// CAMLprim value
// ocaml_git_repository_index( value repo ) {
// 
// }


/* *** Object operations *** */

define_git_ptr_type_manual(object);

// I'm afraid these would require either including libgit2's src/repository.h
// or casting the (git_object *) to an (git_oid *), suggesting libgit2 does
// not approve.
//
// CAMLprim value
// ocaml_git_oid_from_object( value o ) {
//   CAMLparam1(o);
//   CAMLlocal1(id);
//   (const char *) String_val(o);
//   id = caml_alloc_string( GIT_OID_RAWSZ );
//   unless_caml_invalid_argument(
//      git_rawobj_hash( (git_oid *)String_val(id),
//            &((git_object *)Data_custom_val(o)->source.raw) ),
//     "Git.Object.oid");
// CAMLreturn(id);
// }
//
// CAMLprim value
// ocaml_git_otype_from_object( value o ) { ... }

CAMLprim value
_ocaml_git_object_lookup( value repo, value id, git_otype otype ) {
   CAMLparam2(repo,id);
   CAMLlocal1(obj);
   obj = caml_alloc_git_ptr(git_object,manual);
   unless_caml_invalid_argument(
      git_object_lookup( (git_object **)Data_custom_val(obj),
            *(git_repository **)Data_custom_val(repo),
            (git_oid *)String_val(id), otype),
      "Git.Object.lookup");
   CAMLreturn(obj);
}

CAMLprim value
caml_copy_git_oid( const git_oid *oid ) {
   CAMLparam0();
   CAMLlocal1(oc);
   oc = caml_alloc_string( GIT_OID_RAWSZ );
   if (oid)
      memcpy( String_val(oc), oid, GIT_OID_RAWSZ );
   else
      memset( String_val(oc), 0, GIT_OID_RAWSZ );  // not a valid error value
   CAMLreturn(oc);
}

#define define_ocaml_git_simple_fetch_from_git_ptr(N,BASETYPE,CONVERSION) \
CAMLprim value ocaml_git_##N(value v) { \
   CAMLparam1(v); \
   CAMLreturn( CONVERSION ( \
      git_##N( *(BASETYPE **)Data_custom_val(v) \
   )) ); \
}

define_ocaml_git_simple_fetch_from_git_ptr(object_id,git_object,caml_copy_git_oid);  // ocaml_git_object_id
// we may safely cast a (git_[object_type] *) to (git_object *)

// git_object_write


/* *** Tree operations *** */

define_git_ptr_type_manual(tree);  // simple duplication doesn't work?

CAMLprim value ocaml_git_tree_lookup( value repo, value id )
   { return _ocaml_git_object_lookup(repo,id,GIT_OBJ_TREE); }

define_ocaml_git_simple_fetch_from_git_ptr(tree_entrycount,git_tree,Val_int);

CAMLprim value
git_tree_entry_to_ocaml_tree_entry(git_tree_entry *te) {
   CAMLparam0();
   CAMLlocal1(tuple);
   tuple = caml_alloc_tuple(2);
   if (te) {
      Store_field( tuple, 0, caml_copy_string(git_tree_entry_name(te)) );
      Store_field( tuple, 1, caml_copy_git_oid(git_tree_entry_id(te)) );
   } else {
      Store_field( tuple, 0, caml_copy_string("") );
      Store_field( tuple, 1, caml_copy_string("") );      
   }
   CAMLreturn(tuple);
}  // I considered returning an option here, but matching the empty string is just as easy

#define define_ocaml_git_tree_entry(N,CONVERSION) \
CAMLprim value ocaml_git_tree_entry_##N( value tree, value v ) { \
	CAMLparam2(tree,v); \
	git_tree_entry *te = git_tree_entry_##N ( *(git_tree **)Data_custom_val(tree), CONVERSION(v) ); \
	CAMLreturn(git_tree_entry_to_ocaml_tree_entry(te)); \
}

define_ocaml_git_tree_entry(byname,String_val);  // ocaml_git_tree_entry_byname
define_ocaml_git_tree_entry(byindex,Int_val);    // ocaml_git_tree_entry_byindex


/* *** Commit operations *** */

// define_git_ptr_type_manual(commit); 

CAMLprim value ocaml_git_commit_lookup( value repo, value id )
   { return _ocaml_git_object_lookup(repo,id,GIT_OBJ_COMMIT); }

CAMLprim value ocaml_git_commit_time(value commit) {
   CAMLparam1(commit);
   git_time time;
   git_commit *c = *(git_commit **)Data_custom_val(commit);
   time.time = git_commit_time(c);
   time.offset = git_commit_time_offset(c);
   CAMLreturn( git_time_to_ocaml_time(time) );
}  // should submit a patch to libgit2 to use a git_time

#define define_ocaml_git_commit_fetch(NN,C) \
define_ocaml_git_simple_fetch_from_git_ptr(commit_##NN,git_commit,C);

define_ocaml_git_commit_fetch(message_short,caml_copy_string);		  // ocaml_git_commit_message_short
define_ocaml_git_commit_fetch(message,caml_copy_string);		  // ocaml_git_commit_message
define_ocaml_git_commit_fetch(committer,git_signture_to_ocaml_signture);  // ocaml_git_commit_committer
define_ocaml_git_commit_fetch(author,git_signture_to_ocaml_signture);	  // ocaml_git_commit_author

#define define_ocaml_git_simple_fill_ptr_from_git_ptr(N,NEWTYPE,MODE,OLDTYPE,ERROR) \
CAMLprim value ocaml_git_##N(value v) { \
	CAMLparam1(v); \
	CAMLlocal1(r); \
	r = caml_alloc_git_ptr(NEWTYPE,MODE); \
	unless_caml_invalid_argument( \
		git_##N( (NEWTYPE **)Data_custom_val(r), \
			*(OLDTYPE **)Data_custom_val(v) ), \
	ERROR ); \
	CAMLreturn(r); \
}

define_ocaml_git_simple_fill_ptr_from_git_ptr(commit_tree,git_tree,manual,git_commit,"Git.Commit.tree");
// ocaml_git_commit_tree calls git_tree_lookup

// CAMLprim value
// ocaml_git_commit_parents(value commit) {
//    CAMLparam1(commit);
// }


/* *** Commit operations *** */

// define_git_ptr_type_manual(blob);

CAMLprim value ocaml_git_blob_lookup( value repo, value id )
	{ return _ocaml_git_object_lookup(repo,id,GIT_OBJ_BLOB); }

#define define_ocaml_git_blob_fetch(NN,C) \
define_ocaml_git_simple_fetch_from_git_ptr(blob_##NN,git_blob,C);

define_ocaml_git_blob_fetch(rawsize,Val_int); // ocaml_git_blob_size

CAMLprim value ocaml_git_blob_rawcontent(value blob) {
	CAMLparam1(blob);
	CAMLlocal1(c);
	git_blob *b = *(git_blob **)Data_custom_val(blob);
	size_t size = git_blob_rawsize(b);
	c = caml_alloc_string(size);
	memcpy( String_val(c), git_blob_rawcontent(b), size );
	CAMLreturn(c);
}  // null blobs are returnned as empty blobs


/* *** Tag operations *** */

// define_git_ptr_type_manual(tag);

CAMLprim value ocaml_git_tag_lookup( value repo, value id )
	{ return _ocaml_git_object_lookup(repo,id,GIT_OBJ_TAG); }

#define define_ocaml_git_tag_fetch(NN,C) \
define_ocaml_git_simple_fetch_from_git_ptr(tag_##NN,git_tag,C);

define_ocaml_git_tag_fetch(name,caml_copy_string);
define_ocaml_git_tag_fetch(type,Val_int);
define_ocaml_git_tag_fetch(target_oid,caml_copy_git_oid);
define_ocaml_git_tag_fetch(message,caml_copy_string);
define_ocaml_git_tag_fetch(tagger,git_signture_to_ocaml_signture);

define_ocaml_git_simple_fill_ptr_from_git_ptr(tag_target,git_object,manual,git_tag,"Git.Tag.target");
// ocaml_git_tag_target calls git_object_lookup


/* *** Reference operations *** */

define_git_ptr_type_manual(reference);

CAMLprim value
ocaml_git_reference_lookup( value repo, value name ) {
   CAMLparam2(repo,name);
   CAMLlocal1(ref);
   ref = caml_alloc_git_ptr(git_reference,manual);
   unless_caml_invalid_argument(
      git_reference_lookup( (git_reference **)Data_custom_val(ref),
            *(git_repository **)Data_custom_val(repo),
            (char *)String_val(name) ),
      "Git.Reference.lookup");
   CAMLreturn(ref);
}

#define define_ocaml_git_reference_fetch(NN,C) \
define_ocaml_git_simple_fetch_from_git_ptr(reference_##NN,git_reference,C);

define_ocaml_git_reference_fetch(name,caml_copy_string); // ocaml_git_reference_name
define_ocaml_git_simple_fill_ptr_from_git_ptr(reference_resolve,git_reference,manual,git_reference,"Git.Reference.resolve"); // ocaml_git_reference_resolve

// We create the value of type referent_t in ocaml instead of writing a
// ocaml_git_reference_referent function in C.
define_ocaml_git_reference_fetch(type,Val_int);  // ocaml_git_reference_type
define_ocaml_git_reference_fetch(oid,caml_copy_git_oid);   // ocaml_git_reference_oid
define_ocaml_git_reference_fetch(target,caml_copy_string); // ocaml_git_reference_target


/* *** Revwalk operations *** */

// define_git_ptr_type_gced(revwalk); // never a repository object per se


