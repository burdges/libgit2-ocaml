
let msg = "Hello World" ;;

let play_dir = "play" ;;
let playthings = ["git.ml"; "stubs.c"; "Makefile"; "test.ml"; "TODO"; "wrappers.pl"] ;;

print_string ("Initializing play directory : " ^ play_dir ^ "\n") ;;
Unix.system ( String.concat " " ["rm -rf"; play_dir] ) ;;
Unix.mkdir play_dir 0o700 ;;

print_string "Testing Git.Repositort.init\n" ;;
let r = Git.Repository.init play_dir ;;

print_string "Initializing play repository.\n" ;;
Unix.system ( String.concat " " ("cp" :: playthings @ [play_dir]) ) ;;
Unix.chdir play_dir ;;

(*
libgit2 has a bug in it's handling of 

print_string "Testing Git.Index.*\n" ;;
let index = Git.Repository.index r ;;
Git.Index.clear index ;;
let b = Git.Blob.create r ;;
Git.Blob.set_content_from_file b "git.ml" ;;
let open Git.Index in 
	List.iter (fun x -> add index x 0) playthings;
	assert ( (List.length playthings) = (entrycount index) );
	write index ;;
*)

(* Git.Repository.free r ;; *)

Unix.system ( String.concat " " ("git add" :: playthings) ) ;;
Unix.system ("git commit -a -m '" ^ msg ^ "'") ;;


print_string "Testing Git.Repository.open1\n" ;;
let r = Git.Repository.open1 ".git" ;;

print_string "Testing Git.Reference.*\n" ;;
let head = Git.Reference.lookup r "HEAD" ;;
let master = Git.Reference.resolve head ;;

assert ( (Git.Reference.name master) = "refs/heads/master" ) ;;
match Git.Reference.referent head with
	Git.Symbolic "refs/heads/master" -> assert true | _ -> assert false ;;

(*
 * let format_referent = function 
 *  	  Git.Oid oid -> Git.Oid.to_hex oid
 *	| Git.Symbolic s -> s 
 *	| Git.Invalid_referent -> "Invalid reference" ;;
 * print_string (format_referent (Git.Reference.referent master)) ;;
 *)

print_string "Testing Git.Commit.*\n" ;;
let (master_oid,c) = match Git.Reference.referent master with
	  Git.Oid m -> (m, Git.Commit.lookup r m)
	| _ -> assert false ;;
assert (master_oid = (Git.Commit.id c)) ;;

let open Git.Commit in 
	List.iter2 ( fun f x -> assert ((f c) = x) ) 
		[message; message_short ] 
		[msg ^ "\n"; msg ] ;;
print_string "Names : " ;;
print_string (String.concat "\t" (
	let open Git in 
		List.map ( function {name=x;email=y} -> x ^ " <" ^ y ^ ">" ) 
		[ Commit.author c; Commit.committer c ]
) ) ;;
print_string " \n" ;;

(*  let open Git.Commit in assert ( (author c) = (committer c) ) ;;  *)
let t = Git.Commit.tree c ;;
print_string "Testing Git.Tree.*\n" ;;
assert ( (Git.Tree.entrycount t) = (List.length playthings) ) ;;
let todo_oid = Git.TreeEntry.id (Git.Tree.entry_byname t "TODO") ;;

print_string ("Testing Git.Blob.* :\n") ;;
let b = Git.Blob.lookup r todo_oid ;;
print_string (Git.Blob.content b) ;;

let rec range i j = if i > j then [] else i :: (range (i+1) j) ;;
List.iter (
	fun e -> let fn = Git.TreeEntry.name e in
		let oid = Git.TreeEntry.id e in
		let {Unix.st_size=s} = Unix.stat fn in
			assert ( s = (Git.Blob.size (Git.Blob.lookup r oid)) )
	) ( List.map (Git.Tree.entry_byindex t) (range 0 ((Git.Tree.entrycount t) - 1)) )
