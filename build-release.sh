#!/usr/bin/env bash

# Build release tarball/zip from a source package
#
# Copyright (c) 2020 Leorize <leorize+oss@disroot.org>
#
# This script is licensed under the MIT license.

_rev=1 # Bump this variable to force rebuild.
       # This variable does not change the script behavior in anyway, but
       # will trigger a cache mismatch for CI services configured to hash
       # the script as part of the cache key.

usage() {
  cat << EOF
Usage: $0 [-o folder] [-v version] <source>
Build a binary Nim release from the specified source folder. This folder is
assumed to be created from a standard Nim source archive.

Options:
    -o folder   Where to output the resulting artifacts. Defaults to $PWD/output.
    -d folder   Where dependencies are downloaded into. Defaults to $PWD/external.
    -h          This help message.

Environment Variables:
    CC          The compiler used to build csources.
    CFLAGS      Flags to pass to C compilers when building C code.
    LDFLAGS     Flags to pass to C compilers when linking C code.
EOF
}

set -e
set -o pipefail

basedir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
source "$basedir/lib.sh"

output=$PWD/output
outrel=$PWD
deps=$PWD/external
while getopts "o:v:h" curopt; do
  case "$curopt" in
    'o')
      output=$(realpath "$OPTARG")
      ;;
    'd')
      deps=$(realpath "$OPTARG")
      ;;
    'h')
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ $# -lt 1 ]]; then
  echo "$0: missing required argument -- <source>"
  usage
  exit 1
fi

if [[ -e $deps/environment ]]; then
  echo "Sourcing dependencies environment"
  source "$deps/environment"
fi

mkdir -p "$output"

cd "$1"

if [[ $(os) == darwin ]]; then
  : ${CC:=clang}
else
  : ${CC:=gcc}
fi

export PATH=$PWD/bin${PATH:+:$PATH}

cpu=$(arch_from_triple $($CC -dumpmachine))

fold "Build 1-stage csources compiler"
make "-j$()" ucpu="$cpu" CC="$CC"
endfold

buildtmp=$PWD/build

mkdir -p -- "$buildtmp/nim"

export XDG_CONFIG_HOME=$buildtmp

cat <<EOF > "$buildtmp/nim/nim.cfg"
nimcache="$buildtmp/nimcache"
EOF

if [[ -n "$CFLAGS" ]]; then
  echo "passC%=\"\$CFLAGS\"" >> "$buildtmp/nim/nim.cfg"
fi

if [[ -n "$LDFLAGS" ]]; then
  echo "passL%=\"\$LDFLAGS\"" >> "$buildtmp/nim/nim.cfg"
fi

if [[ -e $deps/nim.cfg ]]; then
  echo "Importing configuration from $deps/nim.cfg"
  cat "$deps/nim.cfg" >> "$buildtmp/nim/nim.cfg"
fi

fold "Build koch"
nim c koch
endfold

fold "Build compiler"
./koch boot -d:release
endfold

fold "Build tools"
./koch tools -d:release
endfold

eval $(cat << EOF | nim secret --hints:off 2>/dev/null
echo "version=", NimVersion
echo "os=", hostOS
echo "cpu=", hostCPU
echo "suffix=-", hostOS, "_", hostCPU
quit 0
EOF
)

case "$os" in
  windows)
    fold "Generate release"
    nim c --outdir:. tools/winrelease
    ./winrelease

    case "$cpu" in
      amd64)
        suffix=_x64
        ;;
      i386)
        suffix=_x32
        ;;
      *)
        echo "unsupported cpu: '$cpu', using standard suffix: $suffix"
        ;;
    esac

    cp -t "$output" "web/upload/download/nim-${version}$suffix.zip"
    artifact=$output/nim-${version}$suffix.zip

    echo "Generated release artifact at $artifact"
    echo "$artifact" > "$output/nim.txt"
    endfold
    ;;
  *)
    fold "Build docs"
    # Build release docs
    ./koch doc0 -d:release
    endfold

    fold "Generate release"
    # Cleanup build artifacts
    # TODO: Rework niminst to be able to build binary archives for non-Windows
    rm -rf "$buildtmp"
    find \
      -name .git -prune -o \
      -name c_code -prune -o \
      -name nimcache -prune -o \
      -name build.sh -o \
      -name 'build*.bat' -o \
      -name makefile -o \
      -name '*.o' -o \
      -path '*/compiler/nim' -o \
      -path '*/compiler/nim?' | xargs rm -rf

    cd ..

    srcDir=$(basename "$1")
    if [[ $srcDir != "nim-$version" ]]; then
      # This is for people who build this locally...
      ln -sf "$srcDir" "nim-$version"
    fi

    artifact=$output/nim-$version$suffix.tar
    tar chf "$artifact" "nim-$version"
    xz -9e "$artifact"
    artifact=$artifact.xz

    echo "Generated release artifact at $artifact"
    echo "$artifact" > "$output/nim.txt"
    endfold
    ;;
esac
