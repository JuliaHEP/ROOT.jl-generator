using WrapIt
import TOML

root_version = readchomp(`root-config --version`)

builddir="build/ROOT-" * root_version
witin = "ROOT.wit.in"
wit = joinpath(builddir, "ROOT.wit") 
cxxsrc = [ "Templates.cxx", "Templates.h", "TBranchPtr.h", "Extra.cxx", "Extra.h"]
#makefile = "CMakeLists.txt.in"
makefile = "Makefile.in"
buildfile = "build.jl.in"
jlsrc = ["iROOT.jl", "ROOT.jl", "ROOTex.jl", "demo.jl", "def_args.jl", "move.jl" ]

updatemode = ("--update" ∈ ARGS)
updatemode && println("Update mode")
noclean = ("--noclean" ∈ ARGS)

function samecontents(fpath1, fpath2)
    f1 = open(fpath1)
    f2 = try
        open(fpath2)
    catch
        return false
    end
    same = true
    while(same && !eof(f1) && !eof(f2))
        same &= (read(f1, Char) != read(f2, Char))
    end
    same &= eof(f1) ⊻ eof(f2) #different sizes
    same
end

function cp_if_differs(fpath1, fpath2; kwargs...)
    samecontents(fpath1, fpath2) && return false
    cp(fpath1, fpath2; kwargs...)
end

const cpfunc = updatemode ? cp_if_differs : cp

updatemode = ("--update" ∈ ARGS)
updatemode && println("Update mode")
noclean = ("--noclean" ∈ ARGS)

function samecontents(fpath1, fpath2)
    f1 = open(fpath1)
    f2 = try
        open(fpath2)
    catch
        return false
    end
    same = true
    while(same && !eof(f1) && !eof(f2))
        same &= (read(f1, Char) != read(f2, Char))
    end
    same &= eof(f1) ⊻ eof(f2) #different sizes
    same
end

function cp_if_differs(fpath1, fpath2; kwargs...)
    samecontents(fpath1, fpath2) && return false
    cp(fpath1, fpath2; kwargs...)
end

const cpfunc = updatemode ? cp_if_differs : cp

# It is important to start from an empty src directory. Require to move all previously generated file
if !updatemode && isdir(joinpath(builddir, "ROOT"))
    @error("Directory " * joinpath(builddir, "ROOT") * " is on the way. Please remove it and start again.")
    exit(1)
end

mkpath(joinpath(builddir, "ROOT", "src"))
mkpath(joinpath(builddir, "ROOT", "deps"))

rootincdir = readchomp(`root-config --incdir`)
root_version = readchomp(`root-config --version`)

open(wit, "w") do f
    for l in eachline(witin)
	println(f, replace(l, "%ROOT_INC_DIR%" => rootincdir,
                           "%CLEAN%" => (noclean ? "false" : "true")))
    end
end

rc = wrapit(wit, force=true, cmake=true, output_prefix=builddir, 
            update=updatemode, verbosity=0)

if !isnothing(rc) && rc != 0
    println(stderr, "Failed to produce wrapper code with the wrapit function. Exited with code ", rc, ".")
    exit(rc)
end

run(`$(@__DIR__)/postfix.sh $builddir/ROOT/deps/src`)

function edit_file(file, map)
    tmpfile = joinpath(dirname(file),  "#" * basename(file) * "#")
    changed = false
    try
        open(tmpfile, "w") do fout
            open(file, "r") do fin
                for l in eachline(fin)
                    newl = replace(l, map)
                    println(fout, newl)
                    changed |= (newl != l)
                end
            end
        end
        #Preserve file timestamp if there was no change:
        if(changed)
            mv(tmpfile, file, force=true)
        else
            rm(tmpfile)
        end
    catch e
        @error "Failed to edit file $file. $(e.msg)"
    end
    changed
end

#Code patch: _IO_FILE => FILE (_IO_FILE is not defined on macOS and FILE is anyway cleaner)
let d = joinpath(builddir, "ROOT", "deps", "src"), modif = false
    for f in readdir(d)
        f = joinpath(d, f)
        isfile(f) && (modif = edit_file(f, "_IO_FILE" => "FILE"))
    end
    #in 1 file per class mode, we need to also change the file name:
    oldname = joinpath(d, "Jl_IO_FILE.cxx")
    newname = joinpath(d, "JlFILE.cxx")
    if isfile(oldname) && (!updatemode || !isfile(newname) || !samecontents(oldname, newname))
        mv(oldname, newname, force=true)
    end
end

err = false
#if !isfile(joinpath(builddir, "wrapit.cmake")) || !isdir(joinpath(builddir, "ROOT", "deps", "src"))
##    println(stderr, "Error in the wrapper code generation: file ", joinpath(builddir, "wrapit.cmake"), " is missing.")
#    err = true
#end

if !isfile(joinpath(builddir, "ROOT", "deps", "src", "generated_cxx"))
    println(stderr, "Error in the wrapper code generation: file ", joinpath(builddir, "ROOT", "deps", "src", "generated_cxx"), " is missing.")
    err = true
end

err && exit(1)

if !updatemode
    open(joinpath(builddir, "ROOT", "deps", "wrapit.cmake"), "w") do f
        todrop = builddir * "/ROOT/deps/"
        for l in eachline(joinpath(builddir, "wrapit.cmake"))
	    println(f, replace(l, todrop => ""))
        end
        rm(joinpath(builddir, "wrapit.cmake"))
    end
end

rm(joinpath(builddir, "ROOT", "src", "ROOT-generated.jl"))

for f in cxxsrc
    cpfunc(joinpath("src", f), joinpath(builddir, "ROOT", "deps", "src", f), force=true)
end

#cp(joinpath("src", buildfile), joinpath(builddir, "ROOT", "deps", replace(buildfile, r"\.in$" => "")), force=true)
open(joinpath("src", buildfile)) do fin
    open(joinpath(builddir, "ROOT", "deps", replace(buildfile, r"\.in$" => "")), "w") do fout
        for l in eachline(fin)
            println(fout, replace(l, "%ROOT_VERSION%" => root_version, "%CLEAN%"=> !noclean))
        end
    end
end

cp(joinpath("src", makefile), joinpath(builddir, "ROOT", "deps", replace(makefile, r"\.in$" => "")), force=true)

for f in jlsrc
    cp(joinpath("src", f), joinpath(builddir, "ROOT", "src", f), force=true)
end

let f="jlROOT-veto.h"
    cp(joinpath("src", f), joinpath(builddir, f), force=true)
end
    
open(joinpath(builddir, "ROOT", "deps", "generated_cxx.make"), "w") do fout
    print(fout, "WRAPPER_CXX = Extra.cxx ")
    open(joinpath(builddir, "ROOT", "deps", "src", "generated_cxx")) do fin
        print(fout, readline(fin))
    end
end

#update dependencies in Project.toml:
toml_path=joinpath(builddir, "ROOT", "Project.toml")
project = TOML.parsefile(toml_path)

project["authors"] = [ "Philippe Gras CEA/IRFU" ]

project["deps"]["Conda"] = "8f4d0f93-b110-5947-807f-2305c1781a2d"
project["deps"]["CxxWrap"] = "1f15a43c-97ca-5a2a-ae31-89f07a497df4"
project["deps"]["Libdl"] = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
project["deps"]["Pkg"] = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
project["deps"]["Scratch"] = "6c6a2e73-6563-6170-7368-637461726353"
project["deps"]["TOML"] = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
project["deps"]["UUIDs"] = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

haskey(project, "extras") || (project["extras"] = Dict{String, Any}())
project["extras"]["Test"] = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
project["extras"]["UnROOT"] = "3cd96dde-e98d-4713-81e9-a4a1b0235ce9"

haskey(project, "targets") || (project["targets"] = Dict{String, Any}())
project["targets"]["test"] = ["Test", "UnROOT"]

haskey(project, "compat") || (project["compat"] = Dict{String, Any}())
project["compat"]["julia"] = "1.6"
project["compat"]["Scratch"] = "1.2"
project["compat"]["Conda"] = "1.10"

open(toml_path, "w") do f
    TOML.print(f, project)
end
println("Generated files in $builddir/ROOT")
