DEBUG =

wrappers.h: wrappers.pl
	perl wrappers.pl >wrappers.h

stubs.o: stubs.c wrappers.h
	ocamlc $(DEBUG) -c $<

dll_git2_stubs.so: stubs.o
	ocamlmklib -o  _git2_stubs  $<

git.mli: git.ml
	ocamlc -i $< > $@

git.cmi: git.mli
	ocamlc $(DEBUG) -c $<

git.cmo: git.ml git.cmi
	ocamlc $(DEBUG) -c $<

git.cma:  git.cmo  dll_git2_stubs.so
	ocamlc $(DEBUG) -a  -o $@  $<  -dllib -l_git2_stubs -custom -cclib -lgit2

git.cmx: git.ml git.cmi
	ocamlopt $(DEBUG) -c $<

git.cmxa:  git.cmx  dll_git2_stubs.so
	ocamlopt $(DEBUG) -a  -o $@  $<  -cclib -l_git2_stubs -cclib -lgit2

test: stubs.o git.cmx test.ml
	ocamlopt $(DEBUG) unix.cmxa stubs.o -cclib -lgit2 git.cmx test.ml -o $@


clean:
	rm -f *.[oa] *.so *.cm[ixoa] *.cmxa

