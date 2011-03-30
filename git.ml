

(* *** Git SHA Object Ids *** *)

(* 
 * We implement most libgit2 types like gid_oid as anonymous type strings
 * because ocaml strings are variable length arrays of unsigned characters. 
 * We ignoring oid shortening for now since no other objects need it.
 *)

module type OID = sig
  val hexsz : int
  type t   			 (* let's forget that oids are strings    *)
  val from_hex : string -> t
  val to_hex : t -> string
end ;;

module Oid : OID = struct
  let rawsz = 20 		(* We should import these from git2/oid.h *)
  let hexsz = rawsz * 2 	(* but we don't use them anyway.          *)
  type t = string 
  external from_hex : string -> t = "ocaml_git_oid_from_hex" 
  external to_hex : t -> string = "ocaml_git_oid_to_hex" 
end ;;


(* *** Indexes *** *)

(* The index is the staging area between the repository and the database. *)


module type INDEX = sig
  type t
  type entry = {
	ctime : float;		mtime : float;
	dev : int;		ino : int;		mode : int;
	uid : int;		gid : int;		file_size : int;
	oid : Oid.t;
	flags : int;	flags_extended : int;
	path : string }

  val open_bare : string -> t
  val clear : t -> unit
  val free : t -> unit
  val read : t -> unit
  val write : t -> unit
  val find : t -> int
  val add : t -> string -> int -> unit
  val remove : t -> int -> unit
  val insert : t -> entry -> unit
  val get : t -> int -> entry
  val entrycount : t -> int
end ;;

module Index : INDEX = struct
  type t
  type entry = {
	ctime : float;		mtime : float;
	dev : int;		ino : int;		mode : int;
	uid : int;		gid : int;		file_size : int;
	oid : Oid.t;
	flags : int;	flags_extended : int;
	path : string }

  external open_bare : string -> t	= "ocaml_git_index_open_bare"
  external clear : t -> unit		= "ocaml_git_index_clear"
  external free : t -> unit		= "ocaml_git_index_free"
  external read : t -> unit		= "ocaml_git_index_read"
  external write : t -> unit		= "ocaml_git_index_write"

  external find : t -> int		= "ocaml_git_index_find"
  external add : t -> string -> int -> unit = "ocaml_git_index_add"
  external remove : t -> int -> unit	= "ocaml_git_index_remove"
  external insert : t -> entry -> unit	= "ocaml_git_index_insert"
  external get : t -> int -> entry	= "ocaml_git_index_get"
  external entrycount : t -> int	= "ocaml_git_index_entrycount"
end ;;
  (* Note that git_repository_index is identical to git_index_open_inrepo *)


(* *** Object Databases and Repositories *** *)

(* 
 * We shall maintain the distinction between the repository and the database
 * for forwards compatibility.  For now though, we suppress all lower level
 * commands aimed at custom backends, including databases not contained in a
 * repository and all git_rawobj methods.
 *)

module type ODB = sig
  type t
  val exists : t -> Oid.t -> bool
end ;;

module Odb : ODB = struct
  type t 
  external exists : t -> Oid.t -> bool = "ocaml_git_odb_exists" 
end ;;


module type REPOSITORY = sig
  type t
  val odb : t -> Odb.t
  val init : string -> t
  val init_bare : string -> t
  val open1 : string -> t
  val open2 : string -> string -> string -> string -> t
  val free : t -> unit
  val index : t -> Index.t
end ;;

module Repository : REPOSITORY = struct 
  type t 
  external odb : t -> Odb.t = "ocaml_git_repository_database" 
  external _init : string -> bool -> t	= "ocaml_git_repository_init" 
  let init dir = _init dir false 
  let init_bare dir = _init dir true 
  external open1 : string -> t		= "ocaml_git_repository_open1" 
  external open2 : string -> string -> string -> string -> t
	= "ocaml_git_repository_open2"
  external free : t -> unit		= "ocaml_git_repository_free" 
  external index : t -> Index.t		= "ocaml_git_repository_index"
end ;;



(* *** Abstract Database Objects *** *)

(*
 * We'll require that all object lookup and creation methods explicitly
 * state the object type inside ocaml's type system.  There is actually a
 * GIT_OBJ_ANY = -2 option for git_object_lookup.
 *)

(* You should not rearrange these type constructors because their values  *
 * match the libgit2 enum git_otype and the git file format specification *)

type otype_enum = 	  OType_Ext1	| OType_Commit	| OType_Tree
	| OType_Blob	| OType_Tag 	| OType_Ext2
	| OType_OfsDelta	| OType_RefDelta	| OType_Invalid ;;
let otype_from_int i = match i with 
	  0 -> OType_Ext1 	| 1 -> OType_Commit
	| 2 -> OType_Tree	| 3 -> OType_Blob
	| 4 -> OType_Tag 	| 5 -> OType_Ext2
	| 6 -> OType_OfsDelta	| 7 -> OType_RefDelta
  	| _ -> OType_Invalid ;;

type timeo = { time:float; offset:int } ;;  (* ocaml prefers float for time *)
type signature = { name:string; email:string; time:timeo } ;;

module type OBJECT = sig
  type t
  val id : t -> Oid.t
  val write : t -> unit
end ;;
 (* val otype : t -> int has inheritance issues *)

module Object : OBJECT = struct
  type t 
  external id : t -> Oid.t = "ocaml_git_object_id" 
  external write : t -> unit = "ocaml_git_object_write" 
end ;;


(* *** Tree Database Objects *** *)

(* Trees store directory hierarchies for commit objects *)

module type TREEENTRY = sig
  type t
  val attributes : t -> int
  val name : t -> string
  val id : t -> Oid.t
  val set_attributes : t -> int -> unit
  val set_name : t -> string -> unit
  val set_id : t -> Oid.t -> unit
end ;;

module TreeEntry : TREEENTRY = struct
  type t
  external attributes : t -> int
	= "ocaml_git_tree_entry_attributes"
  external name : t -> string
	= "ocaml_git_tree_entry_name"
  external id : t -> Oid.t
	= "ocaml_git_tree_entry_id"
  external set_attributes : t -> int -> unit
	= "ocaml_git_tree_entry_set_attributes"
  external set_name : t -> string -> unit
	= "ocaml_git_tree_entry_set_name"
  external set_id : t -> Oid.t -> unit
	= "ocaml_git_tree_entry_set_id"
end ;;

module type TREE = sig
  include OBJECT
  val lookup : Repository.t -> Oid.t -> t
  val create : Repository.t -> t
  val entrycount : t -> int
  val entry_byindex : t -> int -> TreeEntry.t
  val entry_byname : t -> string -> TreeEntry.t
  val entries : t -> TreeEntry.t array
  val add_entry : t -> Oid.t -> string -> int -> TreeEntry.t
  val remove_entry_byindex : t -> int -> unit
  val remove_entry_byname : t -> string -> unit
  val clear_entries : t -> unit
end ;;

module Tree : TREE = struct
  include Object
  external lookup : Repository.t -> Oid.t -> t
	= "ocaml_git_tree_lookup"
  external create : Repository.t -> t
	= "ocaml_git_tree_new"

  external entrycount : t -> int
	= "ocaml_git_tree_entrycount" 
  external entry_byindex : t -> int -> TreeEntry.t
	= "ocaml_git_tree_entry_byindex"
  external entry_byname : t -> string -> TreeEntry.t
	= "ocaml_git_tree_entry_byname" 
  let entries tree = Array.init (entrycount tree) (fun i -> entry_byindex tree i)

  external add_entry : t -> Oid.t -> string -> int -> TreeEntry.t
	= "ocaml_git_tree_add_entry"
  external remove_entry_byindex : t -> int -> unit
	= "ocaml_git_tree_remove_entry_byindex"
  external remove_entry_byname : t -> string -> unit
	= "ocaml_git_tree_remove_entry_byname" 

  external clear_entries : t -> unit
	= "ocaml_git_tree_clear_entries" 
end ;;
  (* git_tree_entry_2object appears after all object definitions *)

(* The three functions git_tree_entry_set_id, git_tree_entry_set_name, and *
 * git_tree_entry_set_attributes suggest we must track tree entry pointers *)


(* *** Commit Database Objects *** *)

module type COMMIT = sig
  include OBJECT
  val lookup : Repository.t -> Oid.t -> t
  val time : t -> timeo
  val message_short : t -> string
  val message : t -> string
  val committer : t -> signature
  val author : t -> signature
  val tree : t -> Tree.t
  val parentcount : t -> int
  val parent : t -> int -> t
  val parents : t -> t lazy_t array
  val add_parent : t -> t -> unit
  val set_message : t -> string -> unit
  val set_committer : t -> signature -> unit
  val set_author : t -> signature -> unit
  val set_tree : t -> Tree.t -> unit
end ;;

module Commit : COMMIT = struct
  include Object
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_commit_lookup" 
  external create : Repository.t -> t
	= "ocaml_git_commit_new"
  external time : t -> timeo		= "ocaml_git_commit_time" 
  external message_short : t -> string	= "ocaml_git_commit_message_short" 
  external message : t -> string	= "ocaml_git_commit_message" 
  external committer : t -> signature	= "ocaml_git_commit_committer" 
  external author : t -> signature	= "ocaml_git_commit_author" 
  external tree : t -> Tree.t		= "ocaml_git_commit_tree" 

  external parentcount : t -> int	= "ocaml_git_commit_parentcount"
  external parent : t -> int -> t	= "ocaml_git_commit_parent"
  let parents c = Array.init (parentcount c) (fun i -> lazy (parent c i))
  external add_parent : t -> t -> unit	= "ocaml_git_commit_add_parent"

  (*  external set_message_short : t -> string -> unit	*)
  (*		= "ocaml_git_commit_set_message_short" 	*)
  external set_message : t -> string -> unit
	= "ocaml_git_commit_set_message" 
  external set_committer : t -> signature -> unit
	= "ocaml_git_commit_set_committer" 
  external set_author : t -> signature -> unit
	= "ocaml_git_commit_set_author" 
  external set_tree : t -> Tree.t -> unit
	= "ocaml_git_commit_set_tree" 
end ;;


(* *** Blob Database Objects *** *)

module type BLOB = sig
  include OBJECT
  val lookup : Repository.t -> Oid.t -> t
  val create : Repository.t -> t
  val size : t -> int
  val content : t -> string
  val set_content_from_file : t -> string -> unit
  val set_content : t -> string -> int -> unit
end ;;

module Blob : BLOB = struct
  include Object
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_blob_lookup" 
  external create : Repository.t -> t
	= "ocaml_git_blob_new"
  external size : t -> int             = "ocaml_git_blob_rawsize" 
  external content : t -> string       = "ocaml_git_blob_rawcontent" 
  external set_content_from_file : t -> string -> unit
	= "ocaml_git_blob_set_rawcontent_fromfile"
  external set_content : t -> string -> int -> unit
	= "ocaml_git_blob_set_rawcontent"
  external writefile : Repository.t -> string -> Oid.t
	= "ocaml_git_blob_writefile"
end ;;


(* *** Tag Database Objects *** *)

(* Tags attach permanent names to database objects, ala "April fools release" *)

module type TAG = sig
  include OBJECT
  val lookup : Repository.t -> Oid.t -> t
  val create : Repository.t -> t
  val name : t -> string
  val target_type : t -> otype_enum
  val target_id : t -> Oid.t
  val tagger : t -> signature
  val message : t -> string

  val set_name : t -> string -> unit
  val set_tagger : t -> signature -> unit
  val set_message : t -> string -> unit
  val set_target_id : t -> Oid.t -> unit
end ;;

module Tag : TAG = struct
  include Object
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_tag_lookup" 
  external create : Repository.t -> t
	= "ocaml_git_tag_new"
  external name : t -> string		= "ocaml_git_tag_name" 
  external _target_type : t -> int	= "ocaml_git_tag_type" 
  let target_type tag = otype_from_int (_target_type tag) 
  external target_id : t -> Oid.t	= "ocaml_git_tag_target_oid" 
  external tagger : t -> signature	= "ocaml_git_tag_tagger" 
  external message : t -> string	= "ocaml_git_tag_message" 

  external set_name : t -> string -> unit
	= "ocaml_git_tag_set_name" 
  external set_tagger : t -> signature -> unit
	= "ocaml_git_tag_set_tagger" 
  external set_message : t -> string -> unit
	= "ocaml_git_tag_set_message" 
  external set_target_id : t -> Oid.t -> unit
	= "ocaml_git_tag_set_target_oid"
end ;;


(* *** Union Database Object *** *)

(* Do NOT rearrange this list, their tag values must match git_otype *)
type database_object = Invalid_object
	| Ext1 of Object.t
	| Commit of Commit.t
	| Tree of Tree.t
	| Blob of Blob.t
	| Tag of Tag.t
	| Ext2 of Object.t
	| OfsDelta of Object.t
	| RefDelta of Object.t ;;

external object_lookup : Oid.t -> database_object
	= "ocaml_git_object_lookup" ;;
external tree_entry_2object : TreeEntry.t -> database_object
	= "ocaml_git_tree_entry_2object" ;;
external tag_target : Tag.t -> database_object
	= "ocaml_git_tag_target" ;;
external tag_set_target : Tag.t -> database_object -> unit
	= "ocaml_git_tag_set_target" ;;


(* *** References *** *)

(* References are used to track the heads of each branch *)

type referent_t = Invalid_referent 
	| Oid of Oid.t
	| Symbolic of string

module type REFERENCE = sig
  type t
  val lookup : Repository.t -> string -> t
  val name : t -> string
  val resolve : t -> t
  val referent : t -> referent_t
  val resolution : t -> database_object
  val listall : Repository.t -> int -> string array
end ;;

module Reference : REFERENCE = struct
  type t
  external lookup : Repository.t -> string -> t
       = "ocaml_git_reference_lookup" 
  external name : t -> string	= "ocaml_git_reference_name" 
  external resolve : t -> t	= "ocaml_git_reference_resolve" 

  external _rtype : t -> int      = "ocaml_git_reference_type" 
  external _oid : t -> Oid.t      = "ocaml_git_reference_oid" 
  external _target : t -> string  = "ocaml_git_reference_target" 
  let referent r = match _rtype r with
	1 -> Oid (_oid r) | 2 -> Symbolic (_target r) | _ -> Invalid_referent 
	(* See definition of git_rtype enum in git2/types.h *)

  let resolution r = match referent (resolve r) with
	  Oid id -> object_lookup id
	| Symbolic _ -> Invalid_object
	| Invalid_referent -> Invalid_object
  external listall : Repository.t -> int -> string array
				= "ocaml_git_reference_listall" 
end ;;



