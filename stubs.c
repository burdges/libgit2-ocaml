
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

// Warning : OCaml considers its execptions private
#define FAILURE_EXN 2	// Failure indicates bad user input
#define INVALID_EXN 3	// Invalid argument indicates programming problem

void pass_git_exceptions( int err, char *s, int exn) {
	if (err == 0)	return;  // GIT_SUCCESS = 0
	if (s == NULL)	caml_raise_with_string(exn,s);
	char *buf = String_val(caml_alloc_string(256));
	snprintf(buf,256,"%s : %s",s,git_strerror(err));
	caml_raise_with_string(exn,buf);
}


/* *** Convert git object ids to and from hex *** */

// We handle these manually because the string lengths are fixed,
// and a git_oid "string" may contain nulls.

CAMLprim value
ocaml_git_oid_from_hex( value hex ) {
	CAMLparam1(hex);
	CAMLlocal1(id);
	id = caml_alloc_string( GIT_OID_RAWSZ );
	int err = git_oid_mkstr( (git_oid *)String_val(id),
			(const char *) String_val(hex));
	pass_git_exceptions(err,"Git.Oid.from_hex",INVALID_EXN);
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


/* *** Time and signature conversions *** */

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
static struct custom_operations git_##N##_custom_ops = { \
    identifier:  "Git " #N " manual pointer handling", \
    finalize:    custom_finalize_default, \
    compare:     &custom_ptr_compare, \
    hash:        custom_hash_default, \
    serialize:   custom_serialize_default, \
    deserialize: custom_deserialize_default \
};

#define define_git_ptr_type_gced(N,FREE) \
void custom_git_##N##_ptr_finalize (value v) { \
	CAMLparam1(v); \
	git_##N##_##FREE( *(git_##N **)Data_custom_val(v) ); \
	CAMLreturn; \
} \
static struct custom_operations git_##N##_custom_ops = { \
    identifier:  "Git " #N "GCed pointer handling", \
    finalize:    &custom_git_##N##_ptr_finalize, \
    compare:     &custom_ptr_compare, \
    hash:        custom_hash_default, \
    serialize:   custom_serialize_default, \
    deserialize: custom_deserialize_default \
};


#define caml_alloc_git_ptr(GITTYPE) \
	caml_alloc_custom( & GITTYPE##_custom_ops, \
		sizeof(GITTYPE *), CAMLGC_used_##GITTYPE, CAMLGC_max_git )

// We configure the ocaml garbage collector to close out git structs during
// finilazation here.  Of course, the value used = 0 tells the garbage
// colelctor that only the caml heap size matters.
// see : http://caml.inria.fr/pub/docs/manual-ocaml/manual032.html

#define CAMLGC_max_git			1000000
#define CAMLGC_used_git_index		0
#define CAMLGC_used_git_repository	0
#define CAMLGC_used_git_odb		0
#define CAMLGC_used_git_object		0
#define CAMLGC_used_git_tree		0
#define CAMLGC_used_git_commit		0
#define CAMLGC_used_git_blob		0
#define CAMLGC_used_git_tag		0
#define CAMLGC_used_git_reference	0
#define CAMLGC_used_git_tree_entry	0

#include "wrappers.h"


/* *** Index operations *** */

define_git_ptr_type_manual(index);

wrap_setptr_val1(git_index_open_bare,git_index,
	"Git.Index.open_bare",FAILURE_EXN,
	String_val);

wrap_retunit_ptr1(git_index_clear,
	git_index);
wrap_retunit_ptr1(git_index_free,
	git_index);
wrap_retunit_exn_ptr1(git_index_read,
	"Git.Index.read",INVALID_EXN,
	git_index);
wrap_retunit_exn_ptr1(git_index_write,
	"Git.Index.write",INVALID_EXN,
	git_index);
wrap_retval_ptr1_val1(git_index_find,Val_int, // -1 should throw an exception
	git_index,String_val);
wrap_retunit_exn_ptr1_val2(git_index_add,
	"Git.Index.add",INVALID_EXN,
	git_index,String_val,Int_val);
wrap_retunit_exn_ptr1_val1(git_index_remove,
	"Git.Index.remove",INVALID_EXN,
	git_index,Int_val);
wrap_retval_ptr1(git_index_entrycount,Val_int,
	git_index);

// We're ignoring the nanoseconds since libgit2 doesn't handle them either.

CAMLextern value
ocaml_git_index_insert( value index, value v ) {
	CAMLparam2(index,v);
	git_index_entry entry;
	entry.ctime.seconds = (git_time_t)Double_val(Field(v,0));
	entry.mtime.seconds = (git_time_t)Double_val(Field(v,1));
	entry.dev = Int_val(Field(v,2));
	entry.ino = Int_val(Field(v,3));
	entry.mode = Int_val(Field(v,4));
	entry.uid = Int_val(Field(v,5));
	entry.gid = Int_val(Field(v,6));
	entry.file_size = Int_val(Field(v,7));
	memcpy( &entry.oid, String_val(Field(v,8)), GIT_OID_RAWSZ );
	entry.flags = Int_val(Field(v,9));
	entry.flags_extended = Int_val(Field(v,10));
	entry.path = String_val(Field(v,11));
	int err = git_index_insert( *(git_index **)Data_custom_val(index), &entry );
	pass_git_exceptions(err,"Git.Index.insert",INVALID_EXN);
	CAMLreturn(Val_unit);
}

CAMLextern value
git_index_entry_to_ocaml_index_entry(git_index_entry *entry) {
	CAMLparam0();
	CAMLlocal2(r,oid);
	oid = caml_alloc_string( GIT_OID_RAWSZ );
	memcpy( String_val(oid), &entry->oid, GIT_OID_RAWSZ );
	r = caml_alloc(12,0);
	Store_field(r, 0, caml_copy_double((double)entry->ctime.seconds));
	Store_field(r, 1, caml_copy_double((double)entry->mtime.seconds));
	Store_field(r, 2, Val_int(entry->dev));
	Store_field(r, 3, Val_int(entry->ino));
	Store_field(r, 4, Val_int(entry->mode));
	Store_field(r, 5, Val_int(entry->uid));
	Store_field(r, 6, Val_int(entry->gid));
	Store_field(r, 7, Val_int(entry->file_size));
	Store_field(r, 8, oid);
	Store_field(r, 9, Val_int(entry->flags));
	Store_field(r, 10, Val_int(entry->flags_extended));
	Store_field(r, 11, caml_copy_string(entry->path));
	CAMLreturn(r);
}

wrap_retval_ptr1_val1(git_index_get,git_index_entry_to_ocaml_index_entry,
	git_index, Int_val);


/* *** Repository and object database operations *** */

define_git_ptr_type_manual(odb);  

wrap_retunit_ptr1(git_odb_close,git_odb);

wrap_retval_ptr1_val1(git_odb_exists,Val_bool,git_odb,
	(git_oid *)String_val);


define_git_ptr_type_manual(repository);

wrap_retptr_ptr1(git_repository_database,git_odb,
	"Git.Repository.database",
	git_repository);

wrap_setptr_val2(git_repository_init,git_repository,
	"Git.Repository._init",FAILURE_EXN,
	String_val,Bool_val);

#define git_repository_open1 git_repository_open
wrap_setptr_val1(git_repository_open1,git_repository,
	"Git.Repository.open1",FAILURE_EXN,
	String_val);

wrap_setptr_val4(git_repository_open2,git_repository,
	"Git.Repository.open2",FAILURE_EXN,
	String_val,String_val,String_val,String_val);


wrap_retunit_ptr1(git_repository_free,git_repository);
// Warning : git_repository_close exists only as an extern in repository.h

wrap_setptr_ptr1(git_repository_index,git_index,
	"Git.Repository.index",INVALID_EXN,
 	git_repository);


/* *** Object operations *** */

define_git_ptr_type_manual(object);

CAMLprim value
_ocaml_git_object_lookup( value repo, value id, git_otype otype ) {
	CAMLparam2(repo,id);
	CAMLlocal1(obj);
	obj = caml_alloc_git_ptr(git_object);
	int err = git_object_lookup( (git_object **)Data_custom_val(obj),
			*(git_repository **)Data_custom_val(repo),
			(git_oid *)String_val(id), otype);
	pass_git_exceptions(err,"Git.[object_type].lookup",INVALID_EXN);
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

wrap_retval_ptr1(git_object_id,caml_copy_git_oid,
	git_object);
// we may safely cast a (git_[object_type] *) to (git_object *), btw.

wrap_retval_ptr1(git_object_type,Val_int,
	git_object);

wrap_retunit_exn_ptr1(git_object_write,
	"Git.Object.write",FAILURE_EXN,
	git_object);

// git_object_new


/* *** Tree operations *** */

#define git_tree_custom_ops git_object_custom_ops

define_git_ptr_type_manual(tree_entry);

wrap_retval_ptr1(git_tree_entry_attributes,Val_int,  git_tree_entry);
wrap_retval_ptr1(git_tree_entry_name,caml_copy_string,  git_tree_entry);
wrap_retval_ptr1(git_tree_entry_id,caml_copy_git_oid,  git_tree_entry);
wrap_retunit_ptr1_val1(git_tree_entry_set_attributes,
	git_tree_entry, Int_val);
wrap_retunit_ptr1_val1(git_tree_entry_set_name,
	git_tree_entry, String_val);
wrap_retunit_ptr1_val1(git_tree_entry_set_id,
	git_tree_entry, (git_oid *)String_val);


CAMLprim value ocaml_git_tree_lookup( value repo, value id )
   { return _ocaml_git_object_lookup(repo,id,GIT_OBJ_TREE); }

wrap_setptr_ptr1(git_tree_new,git_tree,
	"Git.Tree.create",INVALID_EXN,
 	git_repository);

wrap_retval_ptr1(git_tree_entrycount,Val_int,  git_tree);

wrap_setptr_ptr1_val3(git_tree_add_entry,git_tree_entry,
	"Git.Tree.add_entry",INVALID_EXN,
 	git_tree, (git_oid *)String_val,String_val,Int_val);

wrap_retptr_ptr1_val1(git_tree_entry_byname,git_tree_entry,
	"Git.tree.entry_byname",
	git_tree,String_val);
wrap_retptr_ptr1_val1(git_tree_entry_byindex,git_tree_entry,
	"Git.tree.entry_byindex",
	git_tree,Int_val);

wrap_retunit_exn_ptr1_val1(git_tree_remove_entry_byname,
	"Git.tree.remove_entry_byname",INVALID_EXN,
	git_tree,String_val);
wrap_retunit_exn_ptr1_val1(git_tree_remove_entry_byindex,
	"Git.tree.remove_entry_byindex",INVALID_EXN,
	git_tree,Int_val);

wrap_retunit_ptr1(git_tree_clear_entries, git_tree);


/* *** Commit operations *** */

#define git_commit_custom_ops git_object_custom_ops

CAMLprim value ocaml_git_commit_lookup( value repo, value id )
   { return _ocaml_git_object_lookup(repo,id,GIT_OBJ_COMMIT); }

wrap_setptr_ptr1(git_commit_new,git_commit,
	"Git.Commit.create",INVALID_EXN,
 	git_repository);

CAMLprim value ocaml_git_commit_time(value commit) {
   CAMLparam1(commit);
   git_time time;
   git_commit *c = *(git_commit **)Data_custom_val(commit);
   time.time = git_commit_time(c);
   time.offset = git_commit_time_offset(c);
   CAMLreturn( git_time_to_ocaml_time(time) );
}  // should submit a patch to libgit2 to use a git_time

#define wrap_retval_commit(NN,C)  wrap_retval_ptr1(NN,C,git_commit)
wrap_retval_commit(git_commit_message_short,caml_copy_string);
wrap_retval_commit(git_commit_message,caml_copy_string);
wrap_retval_commit(git_commit_committer,git_signture_to_ocaml_signture);
wrap_retval_commit(git_commit_author,git_signture_to_ocaml_signture);

wrap_setptr_ptr1(git_commit_tree,git_tree,
	"Git.Commit.tree",INVALID_EXN,
	git_commit);
// ocaml_git_commit_tree calls git_tree_lookup

wrap_retval_commit(git_commit_parentcount, Int_val);
wrap_setptr_ptr1_val1(git_commit_parent,git_commit,
	"Git.Commit.parent",INVALID_EXN,
	git_commit,Int_val);
wrap_retunit_exn_ptr2(git_commit_add_parent,
	"Git.Commit.add_parent",INVALID_EXN,
	git_commit,git_commit);

// wrap_retunit_ptr1_val1(git_commit_set_message_short,git_commit,
//	String_val);
wrap_retunit_ptr1_val1(git_commit_set_message,git_commit,
	String_val);

#define wrap_retunit_pc(FUNCTION,TYPE1,TYPE2,CONVERSION2) \
CAMLprim value ocaml_##FUNCTION(value p1,value v2) { \
        CAMLparam2(p1,v2); \
	TYPE2 c2 = CONVERSION2(v2); \
        FUNCTION( *(TYPE1 **)Data_custom_val(p1), &c2 ); \
        CAMLreturn(Val_unit); \
}

wrap_retunit_pc(git_commit_set_committer,git_commit,
	git_signature,ocaml_signture_to_git_signture_dirty);
wrap_retunit_pc(git_commit_set_author,git_commit,
	git_signature,ocaml_signture_to_git_signture_dirty);

wrap_retunit_exn_ptr2(git_commit_set_tree,
	"Git.Commit.set_tree",INVALID_EXN,
	git_commit,git_tree);


/* *** Blob operations *** */

#define git_blob_custom_ops git_object_custom_ops

CAMLprim value ocaml_git_blob_lookup( value repo, value id )
	{ return _ocaml_git_object_lookup(repo,id,GIT_OBJ_BLOB); }

wrap_setptr_ptr1(git_blob_new,git_blob,
	"Git.Blob.create",INVALID_EXN,
 	git_repository);

#define wrap_retval_blob(NN,C)  wrap_retval_ptr1(NN,C,git_blob)
wrap_retval_blob(git_blob_rawsize,Val_int);

CAMLprim value ocaml_git_blob_rawcontent(value blob) {
	CAMLparam1(blob);
	CAMLlocal1(c);
	git_blob *b = *(git_blob **)Data_custom_val(blob);
	size_t size = git_blob_rawsize(b);
	c = caml_alloc_string(size);
	memcpy( String_val(c), git_blob_rawcontent(b), size );
	CAMLreturn(c);
}  // null blobs are returnned as empty blobs

wrap_retunit_exn_ptr1_val1(git_blob_set_rawcontent_fromfile,
	"Git.Blob.set_content_from_file",INVALID_EXN,
	git_blob,String_val);

CAMLprim value ocaml_git_blob_set_rawcontent(value blob,value b) {
        CAMLparam2(blob,b);
	int err = git_blob_set_rawcontent(
			*(git_blob **)Data_custom_val(blob),
			String_val(b), caml_string_length(b) );
	pass_git_exceptions(err, "Git.Blob.set_content", INVALID_EXN );
	CAMLreturn(Val_unit);
}

CAMLprim value ocaml_git_blob_writefile(value repo,value fn) {
        CAMLparam2(repo,fn);
	CAMLlocal1(id);
	id = caml_alloc_string( GIT_OID_RAWSZ );
	int err = git_blob_writefile( (git_oid *)String_val(id),
			*(git_repository **)Data_custom_val(repo),
			String_val(fn) );
	pass_git_exceptions(err, "Git.Blob.writefile", INVALID_EXN );
        CAMLreturn(id);
}


/* *** Tag operations *** */

#define git_tag_custom_ops git_object_custom_ops

CAMLprim value ocaml_git_tag_lookup( value repo, value id )
	{ return _ocaml_git_object_lookup(repo,id,GIT_OBJ_TAG); }

wrap_setptr_ptr1(git_tag_new,git_tag,
	"Git.Blob.create",INVALID_EXN,
 	git_repository);

#define wrap_retval_tag(NN,C)  wrap_retval_ptr1(NN,C,git_tag)
wrap_retval_tag(git_tag_name,caml_copy_string);
wrap_retval_tag(git_tag_type,Val_int);
wrap_retval_tag(git_tag_target_oid,caml_copy_git_oid);
wrap_retval_tag(git_tag_message,caml_copy_string);
wrap_retval_tag(git_tag_tagger,git_signture_to_ocaml_signture);

wrap_retunit_ptr1_val1(git_tag_set_name,
	git_tag, String_val);
wrap_retunit_pc(git_tag_set_tagger,git_tag,
	git_signature,ocaml_signture_to_git_signture_dirty);
wrap_retunit_ptr1_val1(git_tag_set_message,
	git_tag, String_val);

CAMLprim value
ocaml_git_tag_set_target_oid(value t,value id) {
	CAMLparam2(t,id);
	git_tag *tag = (git_tag *)Data_custom_val(t);
	git_repository *repo = git_object_owner( (git_object *)tag );
	git_object *obj;
	int err = git_object_lookup( &obj, repo, 
			(git_oid *)String_val(id), GIT_OBJ_ANY);
	pass_git_exceptions(err,"Git.Tag.set_target_id : git_object_lookup",INVALID_EXN);
	err = git_tag_set_target(tag,obj);
	pass_git_exceptions(err,"Git.Tag.set_target_id : git_tag_set_target",INVALID_EXN);
	CAMLreturn(Val_unit);
}


/* *** Union object operations *** */

CAMLprim value
ocaml_git_database_object(git_object *obj) {
	CAMLparam0();
	CAMLlocal2(o,r);
	o = caml_alloc_git_ptr(git_object);
	*(git_object **)Data_custom_val(o) = obj;
	r = caml_alloc(1, git_object_type(obj) );  // tag matches to type
	Store_field(r,0, o);
	CAMLreturn(r);
}

CAMLprim value
ocaml_git_object_lookup( value repo, value id ) {
	CAMLparam2(repo,id);
	git_object *obj;
	int err = git_object_lookup( &obj,
			*(git_repository **)Data_custom_val(repo),
			(git_oid *)String_val(id), GIT_OBJ_ANY);
	pass_git_exceptions(err,"Git.object_lookup",INVALID_EXN);
	CAMLreturn( ocaml_git_database_object(obj) );
}

CAMLprim value
ocaml_git_tree_entry_2object( value entry ) {
	CAMLparam1(entry);
	git_object *obj;
	int err = git_tree_entry_2object( &obj, *(git_tree_entry **)Data_custom_val(entry) );
	pass_git_exceptions(err,"Git.tree_entry_2object",INVALID_EXN);
	CAMLreturn( ocaml_git_database_object(obj) );
}  // calls git_object_lookup

CAMLprim value
ocaml_git_tag_target( value tag ) {
	CAMLparam1(tag);
	git_object *obj;
	int err = git_tag_target( &obj, *(git_tag **)Data_custom_val(tag) );
	pass_git_exceptions(err,"Git.tag_target",INVALID_EXN);
	CAMLreturn( ocaml_git_database_object(obj) );
}  // calls git_object_lookup

CAMLprim value
ocaml_git_tag_set_target( value t, value dbo ) {
	CAMLparam2(t,dbo);
	if (Is_block(dbo)) {
		git_object *obj = *(git_object **)Data_custom_val(Field(dbo,0));
		if (git_object_type(obj) != Tag_val(dbo))
			caml_invalid_argument("Git.Tag.set_target : Invalid object, incorrectly annotated object type.");
		int err = git_tag_set_target( *(git_tag **)Data_custom_val(t), obj );
		pass_git_exceptions(err,"Git.Tag.set_target",INVALID_EXN);
	} else // (Is_long(v))
		caml_invalid_argument("Git.Tag.set_target : Invalid object, not even a block.");
	CAMLreturn(Val_unit);
}


/* *** Reference operations *** */

define_git_ptr_type_manual(reference);

wrap_setptr_ptr1_val1(git_reference_lookup,git_reference,
	"Git.Reference.lookup",INVALID_EXN,
	git_repository, (char *)String_val);

#define wrap_retval_reference(NN,C)  wrap_retval_ptr1(NN,C,git_reference)
wrap_retval_reference(git_reference_name,caml_copy_string);

wrap_setptr_ptr1(git_reference_resolve,git_reference,
	"Git.Reference.resolve",INVALID_EXN,
	git_reference);

// We create the value of type referent_t in ocaml instead of writing a
// ocaml_git_reference_referent function in C.
wrap_retval_reference(git_reference_type,Val_int);
wrap_retval_reference(git_reference_oid,caml_copy_git_oid);
wrap_retval_reference(git_reference_target,caml_copy_string);

CAMLprim value ocaml_git_reference_listall( value repo, value flags ) {
	CAMLparam2(repo,flags);
	CAMLlocal1(r);
	git_strarray a; int i;
	int err = git_reference_listall( &a, *(git_repository **)Data_custom_val(repo), Int_val(flags) );
	pass_git_exceptions(err,"Git.Reference.listall",INVALID_EXN);
	r = caml_alloc(a.count, 0);
	for (i=0; i < a.count; i++) {
		Store_field(r, i, caml_copy_string(a.strings[i]) );
	}
	git_strarray_free(&a);
	CAMLreturn(r);
}


/* *** Revwalk operations *** */

// define_git_ptr_type_gced(revwalk); // never a repository object per se


