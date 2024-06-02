# ROOT.jl code generation

Setup to generate code for the [ROOT.jl](https://github.com/JuliaHEP/) package using [WrapIt!](https://github.com/grasph/wrapit). ROOT.jl is a Julia interface to the [ROOT](https://root.cern) C++ framework.

Contents of ROOT.jl generated with this code:
- Project.toml;
- deps directory and its contents;
- src directory and its contents.

The code is generated with `julia -project=generate.jl` command and placed into the `build` subdirectory.

Wrapit configuration including to list of classes to wrap is defined in `ROOT.wit.in`.