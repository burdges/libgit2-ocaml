

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

(*
 * The index is the staging area between the repository and the database.
 * Ergo, any porcelain layer write functionality will need it.
 * We may define it here because the only git type needed will be git_oid.
 *)

module type INDEX = sig
  type t
end ;;

module Index : INDEX = struct
  type t
end ;;


(* *** Object Databases and Repositories *** *)

(* 
 * We shall maintain the distinction between the repository and the database
 * for forwards compatibility.  For now though, we suppress all lower level
 * commands for opening repositories with dissociated paths, databases not
 * contained in a repository, custom backends, and the raw object methods
 * needed for custom backends.
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
  val free : t -> unit
  (* val index : t -> Index.t *)
end ;;

module Repository : REPOSITORY = struct 
  type t 
  external odb : t -> Odb.t = "ocaml_git_repository_database" 
  external _init : bool -> string -> t = "ocaml_git_repository_init" 
  let init = _init false 
  let init_bare = _init true 
  external open1 : string -> t = "ocaml_git_repository_open1" 
  external free : t -> unit = "ocaml_git_repository_free" 
  (* external index : t -> Index.t = "ocaml_git_repository_index" *)
end ;;


(* *** Abstract Database Objects *** *)

(*
 * We'll require that all object lookup and creation methods explicitly
 * state the object type inside ocaml's type system.  There is actually a
 * GIT_OBJ_ANY = -2 option for git_object_lookup.  If we even need this, 
 * it should be implemented as a union type in ocaml.  It appears that
 * git_rawobj only exists for custom backends.
 *)

type otype_enum = 	OType_Ext1	| OType_Commit	| OType_Tree
	| OType_Blob	| OType_Tag 	| OType_Ext2
	| OType_OfsDelta	| OType_RefDelta	| OType_Invalid ;;
let otype_from_int i = match i with 
	  0 -> OType_Ext1 	| 1 -> OType_Commit
	| 2 -> OType_Tree	| 3 -> OType_Blob
	| 4 -> OType_Tag 	| 5 -> OType_Ext2
	| 6 -> OType_OfsDelta	| 7 -> OType_RefDelta
  	| _ -> OType_Invalid ;;
(* All these depends upon the C enums, but upstream changes are unlikely *)

type timeo = { time:float; offset:int } ;;  (* ocaml prefers float for time *)
type signature = { name:string; email:string; time:timeo } ;;

module type OBJECT = sig
  type t
  val id : t -> Oid.t
end ;;
(* val write : t -> unit should occur here, employing libgit2's overloading *
 * val otype : t -> int  is exposed only as git_rawobj.type                 *)

module Object : OBJECT = struct
  type t 
  external id : t -> Oid.t = "ocaml_git_object_id" 
end ;;


(* *** Tree Database Objects *** *)

(* Trees store directory hierarchies for commit objects *)

module type TREE = sig
  include OBJECT
  type entry = string * Oid.t
  val lookup : Repository.t -> Oid.t -> t
  val entrycount : t -> int
  val entry_byindex : t -> int -> entry
  val entry_byname : t -> string -> entry
end ;;
(* We must hide these sloppy entry access methods in favor of some proper  *
 * functional interface, presumably a lazy list using the Lazy module, but *
 * this requires further though on my part, and may depend upon add_entry, *
 * indexes, etc.                                                           *)

module Tree : TREE = struct
  include Object
  type entry = string * Oid.t
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_tree_lookup" 
  external entrycount : t -> int
       = "ocaml_git_tree_entrycount" 
  external entry_byindex : t -> int -> entry
       = "ocaml_git_tree_entry_byindex" 
  external entry_byname : t -> string -> entry
       = "ocaml_git_tree_entry_byname" 
end ;;


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
end ;;

module Commit : COMMIT = struct
  include Object
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_commit_lookup" 
  external time : t -> timeo           = "ocaml_git_commit_time" 
  external message_short : t -> string = "ocaml_git_commit_message_short" 
  external message : t -> string       = "ocaml_git_commit_message" 
  external committer : t -> signature  = "ocaml_git_commit_committer" 
  external author : t -> signature     = "ocaml_git_commit_author" 
  external tree : t -> Tree.t          = "ocaml_git_commit_tree" 
  (* external parents : t -> t list    = "ocaml_git_commit_parents" *)
end ;;


(* *** Blob Database Objects *** *)

module type BLOB = sig
  include OBJECT
  val lookup : Repository.t -> Oid.t -> t
  val size : t -> int
  val content : t -> string
end ;;

module Blob : BLOB = struct
  include Object
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_blob_lookup" 
  external size : t -> int             = "ocaml_git_blob_rawsize" 
  external content : t -> string       = "ocaml_git_blob_rawcontent" 
end ;;


(* *** Tag Database Objects *** *)

(* Tags attach permanent names to database objects, ala "April fools release" *)

module type TAG = sig
  include OBJECT
  val lookup : Repository.t -> Oid.t -> t
  val name : t -> string
  val target_type : t -> otype_enum
  val target_oid : t -> Oid.t
  val message : t -> string
  val tagger : t -> signature
end ;;

module Tag : TAG = struct
  include Object
  external lookup : Repository.t -> Oid.t -> t
       = "ocaml_git_tag_lookup" 
  external name : t -> string          = "ocaml_git_tag_name" 
  external _target_type : t -> int     = "ocaml_git_tag_type" 
  let target_type tag = otype_from_int (_target_type tag) 
  external target_oid : t -> Oid.t     = "ocaml_git_tag_target_oid" 
  external message : t -> string       = "ocaml_git_tag_message" 
  external tagger : t -> signature     = "ocaml_git_tag_tagger" 
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
end ;;

module Reference : REFERENCE = struct
  type t
  external lookup : Repository.t -> string -> t
       = "ocaml_git_reference_lookup" 
  external name : t -> string     = "ocaml_git_reference_name" 
  external resolve : t -> t       = "ocaml_git_reference_resolve" 

  external _rtype : t -> int      = "ocaml_git_reference_type" 
  external _oid : t -> Oid.t      = "ocaml_git_reference_oid" 
  external _target : t -> string  = "ocaml_git_reference_target" 
  let referent r = match _rtype r with
	1 -> Oid (_oid r) | 2 -> Symbolic (_target r) | _ -> Invalid_referent 
	(* See definition of git_rtype enum in git2/types.h *)
end ;;


(* *** Union Database Object *** *)

(* Isn't yet clear whether this is a wise move. *)

(*

type object_types = Ext1
     | Commit of Commit.t
     | Tree of Tree.t
     | Blob of Blob.t
     | Tag of Tag.t
     | Ext2
     |
     |  ;;

val tag_target_obj : Tag.t -> object_types
val reference_referent_obj : Reference.t -> object_types

*)

