Git.stubs.o: Git.stubs.c
	ocamlc -c $<

dll_git2_stubs.so: Git.stubs.o
	ocamlmklib  -o  _git2_stubs  $<

Git.mli: Git.ml
	ocamlc -i $< > $@

Git.cmi: Git.mli
	ocamlc -c $<

Git.cmo: Git.ml Git.cmi
	ocamlc -c $<

Git.cma:  Git.cmo  dll_git2_stubs.so
	ocamlc -a  -o $@  $<  -dllib -l_git2_stubs -custom -cclib -lgit2

Git.cmx: Git.ml Git.cmi
	ocamlopt -c $<

Git.cmxa:  Git.cmx  dll_git2_stubs.so
	ocamlopt -a  -o $@  $<  -cclib -l_git2_stubs -cclib -lgit2

test: Git.stubs.o Git.cmx test.ml
	ocamlopt unix.cmxa Git.stubs.o -cclib -lgit2 Git.cmx test.ml -o $@


clean:
	rm -f *.[oa] *.so *.cm[ixoa] *.cmxa

