(lang dune 2.9)
(name lua-ml)
(generate_opam_files true)

(maintainers "Daniil Baturin <daniil+opam@baturin.org>")
(authors "Norman Ramsey <nr@cs.tufts.edu>" "Christian Lindig <lindig@gmail.com>")
(source (github lindig/lua-ml))
(license "Two-clause BSD")

(package
  (name lua-ml)
  (synopsis "An embeddable Lua 2.5 interpreter implemented in OCaml")
  (depends
    (ocaml (>= "4.07.0"))))
