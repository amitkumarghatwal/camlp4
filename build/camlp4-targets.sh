#!/bin/sh

############################################################################
#                                                                          #
#                                   OCaml                                  #
#                                                                          #
#          Nicolas Pouillard, projet Gallium, INRIA Rocquencourt           #
#                                                                          #
#  Copyright  2007   Institut National de Recherche  en  Informatique et   #
#  en Automatique.  All rights reserved.  This file is distributed under   #
#  the terms of the GNU Library General Public License, with the special   #
#  exception on linking described in LICENSE at the top of the Camlp4      #
#  source tree.                                                            #
#                                                                          #
############################################################################

CAMLP4_BYTE="\
  camlp4/Camlp4.cmo \
  camlp4/Camlp4Top.cmo \
  camlp4/camlp4prof.byte$EXE \
  camlp4/mkcamlp4.byte$EXE \
  camlp4/camlp4.byte$EXE \
  camlp4/camlp4fulllib.cma"
CAMLP4_NATIVE="\
  camlp4/Camlp4.cmx \
  camlp4/camlp4prof.native$EXE \
  camlp4/mkcamlp4.native$EXE \
  camlp4/camlp4.native$EXE \
  camlp4/camlp4fulllib.cmxa"

for i in camlp4boot camlp4r camlp4rf camlp4o camlp4of camlp4oof camlp4orf; do
  CAMLP4_BYTE="$CAMLP4_BYTE camlp4/$i.byte$EXE camlp4/$i.cma"
  CAMLP4_NATIVE="$CAMLP4_NATIVE camlp4/$i.native$EXE"
done

cd ./camlp4
for dir in Camlp4Parsers Camlp4Printers Camlp4Filters; do
  for file in $dir/*.ml; do
    base=camlp4/$dir/`basename $file .ml`
    CAMLP4_BYTE="$CAMLP4_BYTE $base.cmo"
    CAMLP4_NATIVE="$CAMLP4_NATIVE $base.cmx $base$O"
  done
done
cd ..
