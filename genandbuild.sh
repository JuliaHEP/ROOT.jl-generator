#!/bin/bash

help(){
cat <<EOF
Usage: genandbuid.sh DESTDIR

   Generate code and copy it to DESTDIR (ROOT.jl top directory).

   --force: force deletion of DESTDIR/src, DESTDIR/deps, and DESTDIR/Project.toml
   --update: enable update mode
   --rootfromenv: generate the code from the ROOT installation of the shell environment
                  instead of from ROOT_jll
   --verbosity N: set wrapit verbosity level
EOF
}

temp=`getopt -o h --long update,noclean,nobuild,force,verbosity:,rootfromenv \
     -n 'genandbuild.sh' -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$temp"

unset gen_opts
unset updatemode
unset force
unset nobuild
unset rootfromenv

while true ; do
    case "$1" in
        -h|--help) help; exit 0;;
        --update) gen_opts="$gen_opts --update"; updatemode=y; shift;;
        --noclean) gen_opts="$gen_opts --noclean"; shift;;
        --force) force=y; shift;;
        --nobuild) nobuild=y; shift;;
        --rootfromenv) rootfromenv=y; shift;;
        --verbosity) gen_opts="$gen_opts --verbosity $2"; shift 2;;
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
gendir="`pwd`"

if [ -z "$rootfromenv" ]; then
    ROOTSYS="`julia --project="$gendir" -e 'import ROOT_jll; print(ROOT_jll.artifact_dir)'`"
    [ $? != 0 -o -z "$ROOTSYS" ] && die "Failed to set ROOTSYS. Please check that ROOT_jll is in the Project.toml file of $rootjl project and that the project is instantiated."
    
    [ -f "$ROOTSYS/bin/thisroot.sh" ] || die "File $ROOTSYS/bin/thisroot.sh. Failed to set ROOT environment."
    
    source "$ROOTSYS/bin/thisroot.sh"
fi

root_version=`root-config --version`
if [ $? = 0 ]; then
    echo "Code will be built for ROOT version $root_version"
else
    die "root-config command not found. Make sure ROOT binary directory is included in the list defined by the environment variable PATH"
fi

[ -d "$rootjl" ] || mkdir "$rootjl" || die "Directory $rootjl not found. The passed argument must be a valid directory."


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


[ "$updatemode" = y  ] || rm -r build/

julia --project=. generate.jl $gen_opts || die "Failed to generate code"

cd "$rootjl" || die "Failed to enter directory $rootjl"

cp -a "$gendir/build/ROOT-$root_version/ROOT/"{src,deps,Project.toml} . || die "Failed to copy fails. Check input path in `basename "$myself"`"

[ -d misc ] || mkdir misc || die "Failed to create `pwd`/misc directory"
cp -a "$gendir/build/ROOT-$root_version/"{jlROOT-report.txt,jlROOT-veto.h,ROOT.wit} misc/

# src/ROOTdoc.jl needed to import ROOT
[ -f src/ROOTdoc.jl ] || touch src/ROOTdoc.jl

[ "$nobuild" = y ] || julia --project=. -e 'import Pkg; Pkg.instantiate(); import ROOTprefs; ROOTprefs.set_use_root_jll(false); ROOTprefs.set_ROOTSYS(nothing); import ROOT;' # import Pkg; Pkg.test()'

cat <<EOF
**********************************************************************
  Beware this script has modified the contents of '$rootjl' directory.
**********************************************************************
EOF

