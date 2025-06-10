#!/bin/bash

help(){
cat <<EOF
Usage: genandbuid.sh DESTDIR

   Generate code and copy it to DESTDIR (ROOT.jl top directory).

   --force: force deletion of DESTDIR/src, DESTDIR/deps, and DESTDIR/Project.toml
EOF
}

temp=`getopt -o h --long update,noclean,nobuild,force \
     -n 'genandbuild.sh' -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$temp"

unset gen_opts
unset updatemode
unset force
unset nobuild

while true ; do
    case "$1" in
        -h|--help) help; exit 0;;
        --update) gen_opts="$gen_opts --update"; updatemode=y; shift;;
        --noclean) gen_opts="$gen_opts --noclean"; shift;;
        --force) force=y; shift;;
        --nobuild) nobuild=y; shift;;
        --) shift ; break ;; #end of options. It remains only the args.
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

if [ $# != 1 ]; then
    help
    exit 1
fi


die(){
  echo "$@" 1>&2
  exit 1
}

rootjl="$1"
root_version=`root-config --version`
if [ $? = 0 ]; then
    echo "Code will be built for ROOT version $root_version"
else
    die "root-config command not found. Make sure ROOT binary directory is included in the list defined by the environment variable PATH"
fi

[ -d "$rootjl" ] || die "Directory $rootjl not found. The passed argument must be a valid directory."


if [ "$force" = y ]; then 
   rm -r "$rootjl"/{src,deps,Project.toml}
else
   dirs=""
   for d in src deps Project.toml; do
      [ -e "$rootjl/$d" ] && dirs="$dirs $d"
   done 

   if [ -n "$dirs" ]; then
      die "Directory $rootjl already contains $dirs. Please restart after removing this (these) file(s) or directory(ies). Alternatively the option --force can be used." 1>&2
   fi
fi


gendir="`pwd`"

[ "$updatemode" = y  ] || rm -r build/

julia --project=. generate.jl $gen_opts || die "Failed to generate code"

cd "$rootjl" || die "Failed to enter directory $rootjl"

cp -a "$gendir/build/ROOT-$root_version/ROOT/"{src,deps,Project.toml} . || die "Failed to copy fails. Check input path in `basename "$myself"`"

[ -d misc ] || mkdir misc || die "Failed to create `pwd`/misc directory"
cp -a "$gendir/build/ROOT-$root_version/"{jlROOT-report.txt,jlROOT-veto.h,ROOT.wit} misc/

#julia --project=. -e 'import Pkg; Pkg.build(verbose=true); Pkg.test()'
[ "$nobuild" = y ] || julia --project=. -e 'import ROOTprefs; ROOTprefs.use_root_jll!(false); ROOTprefs.set_ROOTSYS!(nothing); import ROOT; import Pkg; Pkg.test()'

cat <<EOF
**********************************************************************
  Beware this script has modified the contents of '$rootjl' directory.
**********************************************************************
EOF

