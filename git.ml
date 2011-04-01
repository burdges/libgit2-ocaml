

(* *** Git SHA Object Ids *** *)

(* We implement gid_oid as anonymous type strings because ocaml strings	 *
 * are variable length arrays of unsigned characters. We ignoring oid	 *
 * shortening for now since no other objects need it. 			 *)

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


(* *** Object Databases  *** *)

(* For now, we suppress all lower level database routines aimed at custom *
 * backends, including databases not contained in a repository and all	  *
 * git_rawobj methods.							  *)

module type ODB = sig
  type t
  val exists : t -> Oid.t -> bool
end ;;

module Odb : ODB = struct
  type t 
  external exists : t -> Oid.t -> bool = "ocaml_git_odb_exists" 
end ;;

(* TODO : ODB streams methods? *)


(* *** Repositories *** *)

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


(* *** Database Object Types *** *)

type object_t
type commit_t
type tree_t
type blob_t
type tag_t

(* You should not rearrange these type constructors because their values  *
 * match the libgit2 enum git_otype and the git file format specification *)

type object_u = Invalid_object
	| Ext1 of object_t
	| Commit of commit_t
	| Tree of tree_t
	| Blob of blob_t
	| Tag of tag_t
	| Ext2 of object_t
	| OfsDelta of object_t
	| RefDelta of object_t ;;

type object_type = 	
  	  Ext1_e	| Commit_e	| Tree_e
	| Blob_e	| Tag_e 	| Ext2_e
	| OfsDelta_e	| RefDelta_e	| Invalid_e ;;

type timeo = { time:float; offset:int } ;; (* ocaml prefers float for time *)
type signature = { name:string; email:string; time:timeo } ;;


(* *** Unspecified Database Objects *** *)

(* All the methods implemented for general objects must be reimplemented   *
 * inside each object type's module because include would produce multiple *
 * definitions of t and ocaml's class system seems excessive here.         *)

module type OBJECT = sig
  type t = object_t
  val id : t -> Oid.t
  val owner : t -> Repository.t
  val lookup : Oid.t -> object_u
end ;;

module Object : OBJECT = struct
  type t = object_t
  external id : t -> Oid.t		= "ocaml_git_object_id" 
  external owner : t -> Repository.t	= "ocaml_git_object_owner" 
  external lookup : Oid.t -> object_u
	= "ocaml_git_object_lookup" ;;
end ;;


(* *** Tree Database Objects *** *)

(* Trees store directory hierarchies for commit objects *)

module type TREEENTRY = sig
  type t
  val attributes : t -> int
  val name : t -> string
  val id : t -> Oid.t
  val obj : Repository.t -> t -> object_u
end ;;

module TreeEntry : TREEENTRY = struct
  type t
  external attributes : t -> int	= "ocaml_git_tree_entry_attributes"
  external id : t -> Oid.t		= "ocaml_git_tree_entry_id"
  external name : t -> string		= "ocaml_git_tree_entry_name"
  external obj : Repository.t -> t -> object_u
	= "ocaml_git_tree_entry_2object" ;;
end ;;

module type TREE = sig
  type t = tree_t
  val lookup : Repository.t -> Oid.t -> t
  val id : t -> Oid.t
  val owner : t -> Repository.t
  val entrycount : t -> int
  val entry_byindex : t -> int -> TreeEntry.t
  val entry_byname : t -> string -> TreeEntry.t
  val entries : t -> TreeEntry.t array
end ;;

module Tree : TREE = struct
  type t = tree_t
  external lookup : Repository.t -> Oid.t -> t
	= "ocaml_git_tree_lookup"
  external id : t -> Oid.t		= "ocaml_git_object_id" 
  external owner : t -> Repository.t	= "ocaml_git_object_owner" 
  external entrycount : t -> int
	= "ocaml_git_tree_entrycount" 
  external entry_byindex : t -> int -> TreeEntry.t
	= "ocaml_git_tree_entry_byindex"
  external entry_byname : t -> string -> TreeEntry.t
	= "ocaml_git_tree_entry_byname" 
  let entries tree = Array.init (entrycount tree) (fun i -> entry_byindex tree i)
end ;;


(* *** Commit Database Objects *** *)

module type COMMIT = sig
  type t = commit_t
  val id : t -> Oid.t
  val owner : t -> Repository.t
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
  val create : Repository.t -> string -> signature -> signature -> string -> Oid.t -> Oid.t array -> Oid.t
  val create_o : Repository.t -> string -> signature -> signature -> string -> Tree.t -> t array -> Oid.t
end ;;

module Commit : COMMIT = struct
  type t = commit_t
  external id : t -> Oid.t		= "ocaml_git_object_id" 
  external owner : t -> Repository.t	= "ocaml_git_object_owner" 
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_commit_lookup" 
  external time : t -> timeo		= "ocaml_git_commit_time" 
  external message_short : t -> string	= "ocaml_git_commit_message_short" 
  external message : t -> string	= "ocaml_git_commit_message" 
  external committer : t -> signature	= "ocaml_git_commit_committer" 
  external author : t -> signature	= "ocaml_git_commit_author" 
  external tree : t -> Tree.t		= "ocaml_git_commit_tree" 

  external parentcount : t -> int	= "ocaml_git_commit_parentcount"
  external parent : t -> int -> t	= "ocaml_git_commit_parent"
  let parents c = Array.init (parentcount c) (fun i -> lazy (parent c i))

  external create : Repository.t -> string -> signature -> signature -> string -> Oid.t -> Oid.t array -> Oid.t
	= "ocaml_git_commit_create_bytecode" "ocaml_git_commit_create"
  external create_o : Repository.t -> string -> signature -> signature -> string -> Tree.t -> t array -> Oid.t
	= "ocaml_git_commit_create_o_bytecode" "ocaml_git_commit_create_o"
end ;;


(* *** Blob Database Objects *** *)

module type BLOB = sig
  type t = blob_t
  val id : t -> Oid.t
  val owner : t -> Repository.t
  val lookup : Repository.t -> Oid.t -> t
  val size : t -> int
  val content : t -> string
  val create_fromfile : Repository.t -> string -> Oid.t
  val create_frombuffer : Repository.t -> string -> Oid.t
end ;;

module Blob : BLOB = struct
  type t = blob_t
  external id : t -> Oid.t		= "ocaml_git_object_id" 
  external owner : t -> Repository.t	= "ocaml_git_object_owner" 
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_blob_lookup" 
  external size : t -> int		= "ocaml_git_blob_rawsize" 
  external content : t -> string	= "ocaml_git_blob_rawcontent" 
  external create_fromfile : Repository.t -> string -> Oid.t
	= "ocaml_git_blob_create_fromfile"
  external create_frombuffer : Repository.t -> string -> Oid.t
	= "git_blob_create_frombuffer"
end ;;


(* *** Tag Database Objects *** *)

(* Tags attach permanent names to database objects, ala "April fools release" *)

module type TAG = sig
  type t = tag_t
  val id : t -> Oid.t
  val owner : t -> Repository.t
  val lookup : Repository.t -> Oid.t -> t
  val create : Repository.t -> t
  val name : t -> string
  val target : t -> object_u
  val target_type : t -> object_type
  val target_id : t -> Oid.t
  val tagger : t -> signature
  val message : t -> string

  val create : Repository.t -> string -> Oid.t -> object_type -> signature -> string -> Oid.t
  val create_o : Repository.t -> string -> object_u -> signature -> string -> Oid.t
end ;;

module Tag : TAG = struct
  type t = tag_t
  external id : t -> Oid.t		= "ocaml_git_object_id" 
  external owner : t -> Repository.t	= "ocaml_git_object_owner" 
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_tag_lookup" 
  external name : t -> string		= "ocaml_git_tag_name" 
  external target : t -> object_u	= "ocaml_git_tag_target"
  external target_type : t -> object_type = "ocaml_git_tag_type" 
  external target_id : t -> Oid.t	= "ocaml_git_tag_target_oid" 
  external tagger : t -> signature	= "ocaml_git_tag_tagger" 
  external message : t -> string	= "ocaml_git_tag_message" 

  external create : Repository.t -> string -> Oid.t -> object_type -> signature -> string -> Oid.t
	= "ocaml_git_tag_create_bytecode" "ocaml_git_tag_create" ;; 
  external create_o : Repository.t -> string -> object_u -> signature -> string -> Oid.t
	= "ocaml_git_tag_create_o" ;;
end ;;


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
  val resolution : t -> object_u
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
	  Oid id -> Object.lookup id
	| Symbolic _ -> Invalid_object
	| Invalid_referent -> Invalid_object
  external listall : Repository.t -> int -> string array
				= "ocaml_git_reference_listall" 
end ;;



