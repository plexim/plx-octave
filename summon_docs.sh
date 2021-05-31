#!/bin/bash

set -o errexit
set -o pipefail

octver=4.4.1

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
tmpdir=`mktemp -d`

curl -L https://ftp.gnu.org/gnu/octave/octave-$octver.tar.xz | tar xv -C $tmpdir --strip-components=4 octave-$octver/doc/interpreter/octave.html

patch -d $tmpdir -p1 < $scriptdir/common_files/doc_jsonencode_jsondecode.patch

tar -cvzf octave-$octver-doc.tar.gz -C $tmpdir .

