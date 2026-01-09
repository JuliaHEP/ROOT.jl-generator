module DoxyReader

using ..ROOTdocDB
using ..ROOTdocDB: colonsubstitute
using TextWrap: print_wrapped
using PrettyTables: pretty_table, tf_markdown
import ROOT

export Conn, filldb

using EzXML

mutable struct State
    start::Bool
    list_depth::Int
    item_num::Vector{Union{Int, Nothing}} #item number in case of ordered list
    item_ipara::Int #When in an item, counter of the paragraph within the item
    verbatim::Bool
end

State() = State(true, 0, Bool[], false, false)

Base.copy(x::State) = State(x.start, x.list_depth, copy(x.item_num), x.item_ipara, x.verbatim)

struct MyIO{T<:IO} <: IO
    base::T
    nindents::Ref{Int}
    nchars::Ref{Int}
    indent::Ref{Bool}
    ntailnewlines::Ref{Int}
    lineprefix::Ref{String}
    tomarkdown::Ref{Bool}
end

MyIO(base::IO, nindents = Ref(0)) = MyIO(base, nindents, Ref(0), Ref(true), Ref(1), Ref(""), Ref(false))
Base.convert(::Type{MyIO}, io::IO) = (io isa MyIO ? io : MyIO(io))

indent(io::MyIO) = (io.nindents[] += 1)
unindent(io::MyIO) = (io.nindents[] = max(0, io.nindents[] - 1))

#Base.write(io::MyIO, x::UInt8) = Base.write(io.base, x::UInt8)


function Base.write(io::MyIO, x::Union{Char, UInt8})
    if isnewline(x);
        io.indent[] = true
        io.ntailnewlines[] += 1
    else
        io.ntailnewlines[] = 0
        if io.indent[]
            write(io.base, io.lineprefix[], "    " ^ io.nindents[])
            io.indent[] = false
        end
    end
    io.nchars[] += 1
    if io.tomarkdown[] && (x ∈ ["~", "_", "*", "`", "#" ])
        write(io.base, "\\")
    end
    write(io.base, x)
end

Base.write(io::MyIO, x::Char) = invoke(Base.write, Tuple{MyIO, Union{Char, UInt8}}, io, x)

Base.write(io::MyIO, x::UInt8) = invoke(Base.write, Tuple{MyIO, Union{Char, UInt8}}, io, x)

Base.take!(io::MyIO) = Base.take!(io.base)

function Base.write(io::MyIO, s::String)
    for c in s
        write(io, c)
    end
end


isnewline(x::Char) = (x == '\n' || x == '\r')
isnewline(x::UInt8) = (x == UInt8('\n') || x == UInt8('\r')) # or false ?!?

#converts newlines from MacOS ≤ 9.x and Window to Unix "\n" convention
norm_linefeed(s) = replace(s, "\r\n"=>"\n", "\r"=>"\n")

const refurl = "https://root.cern/doc/v636/"

function doxy2cxxtype(doxytypename)
    map = Dict()
    Base.get(map, doxytypename, doxytypename)
end

function doxy2jltype(doxytypename; returntype = false, constmethod = false)

    result = doxytypename

    if returntype
        result= replace(result, r"^char \*$" => "Union{String, Vector{CxxChar}}")
    end

    result = replace(result,
                     r"^const char \*$"        => "String",
                     r"\bstd::string\b"        => "StdString",
                     r"\bstd::vector\b"        => "StdVector",
                     r"< "                     => "{",
                     r" >"                     => "}",
                     
                     #std types
                     r"\bvoid\b"               => "Nothing",
                     r"\bfloat\b"              => "Float32",
                     r"\bdouble\b"             => "Float64",
                     r"\bunsigned char\b"      => "UInt8",
                     r"\bunsigned short\b"     => "UInt16",
                     r"\bunsigned int\b"       => "UInt32",
                     r"\bunsigned long\b"      => "UInt64",
                     r"\bunsigned long long\b" => "UInt64",
                     r"\bchar\b"               => "Int8",
                     r"\bshort\b"              => "Int16",
                     r"\bint\b"                => "Int32",
                     r"\bbool\b"               => "Bool",
                     r"\blong\b"               => "Int64",
                     r"\blong long\b"          => "Int64",
                     r"\bsize_t\b"             => "Int64",
                     r"\bssize_t\b"             => "Int64",
                     
                     #Types defined in ROOT (see RtypesCore.h)
                     r"\bChar_t\b"       => "Int8",     #Signed Character 1 byte (char)
                     r"\bUChar_t\b"      => "UInt8",    #Unsigned Character 1 byte (unsigned char)
                     r"^const Char_t \*$"=> "String",
                     r"\bShort_t\b"      => "Int16",    #Signed Short integer 2 bytes (short)
                     r"\bUShort_t\b"     => "UInt16",   #Unsigned Short integer 2 bytes (unsigned short)
                     r"\bInt_t\b"        => "Int32",    #Signed integer 4 bytes
                     r"\bUInt_t\b"       => "UInt32",   #Unsigned int,eger 4 bytes
                     r"\bSeek_t\b"       => "Cint",     #File pointer (int)
                     r"\bLong_t\b"       => "Int64",    #Signed long integer 8 bytes (long)
                     r"\bULong_t\b"      => "UInt64",   #Unsigned long integer 8 bytes (unsigned long)
                     r"\bFloat_t\b"      => "Float32",  #Float 4 bytes (float)
                     r"\bFloat16_t\b"    => "Float16",  #Float 4 bytes written with a truncated mantissa
                     r"\bDouble_t\b"     => "Float64",  #Double 8 bytes
                     r"\bDouble32_t\b"   => "Float64",  #Double 8 bytes in memory, written as a 4 bytes float
                     r"\bLongDouble_t\b" => "Double64", #Long Double. Needs the DoubleFloats package
                     r"\bText_t \*\b"     => "String",   #General string (char)
                     r"\bBool_t\b"       => "Bool",     #Boolean (0=false, 1=true) (bool)
                     r"\bByte_t\b"       => "UInt8",    #Byte (8 bits) (unsigned char)
                     r"\bVersion_t\b"    => "Int16",    #Class version identifier (short)
                     r"^(const )?Option_t \*$" => "String",   #Option string (const char)
                     r"\bSsiz_t\b"       => "int",      #String size (int)
                     r"\bReal_t\b"       => "float",    #TVector and TMatrix element type (float)
                     r"\bLong64_t\b"     => "Int64",    #Portable signed long integer 8 bytes
                     r"\bULong64_t\b"    => "UInt64",   #Portable unsigned long integer 8 bytes
                     r"\bLongptr_t\b"    => "Int64",    #Integer large enough to hold a pointer
                     r"\bULongptr_t\b"   => "UInt64",   #Unsigned integer large enough to hold a pointer
                     r"\bAxis_t\b"       => "Float64",  #Axis values type (double)
                     r"\bStat_t\b"       => "Float64",  #Statistics type (double)
                     r"\bFont_t\b"       => "Int16",    #Font number (short)
                     r"\bStyle_t\b"      => "Int16",    #Style number (short)
                     r"\bMarker_t\b"     => "Int16",    #Marker number (short)
                     r"\bWidth_t\b"      => "Int16",    #Line width (short)
                     r"\bColor_t\b"      => "Int16",    #Color number (short)
                     r"\bSCoord_t\b"     => "Int16",    #Screen coordinates (short)
                     r"\bCoord_t\b"      => "Float64",  #Pad world coordinates (double)
                     r"\bAngle_t\b"      => "Float32",  #Graphics angle (float)
                     r"\bSize_t\b"       => "Float32",  #Attribute size (float)
                     ) |> x->replace(x, "\bOption_t\b" => "Int8", # if not replaced by Option_t *, const char *, etc.
                                     "\bChar_t\b"   => "Int8",
                                     "\bchar\b"     => "Int8")
    tmp = result
    basetype = result
    head = ""
    tail = ""
    i = 0
    #resolve pointers and references:
    while true
        i+=1
        m = match(r"^(const )?(.*) ([*&])", tmp)
        if isnothing(m)
            basetype = tmp
            break
        else
            constspec = isnothing(m.captures[1]) ? "" : "Const"
            tmp = m.captures[2]
            indirection = m.captures[3] == "*" ? "Ptr" : "Ref"
            head *= if returntype
                constspec * "Cxx" * indirection * "{"
            else
                "By" * constspec * indirection * "{"
            end
            tail *= "}"
        end

        if i > 20
            error("Too many loops.")
        end
    end

    juliatypes = [ "Float16", "Float32", "Float64", "Bool", "Char",
                   "Int8", "UInt8", "Int16", "UInt16", "Int32", "UInt32",
                   "Int64", "Integer","UInt64", "Int128", "UInt128","Nothing" ]

    head = if basetype ∈ juliatypes
        replace(head, "Ref" => "Ref2", "Ptr" => "Ptr2")
    else
        replace(head, "Ref" => "Ref1", "Ptr" => "Ptr1")
    end

    if isempty(head) && !(basetype ∈ juliatypes) && !isempty(basetype)
        head = "ByCopy{"
        tail = "}"
    end

    #remove const decl from the base type and resolves ::
    basetype = replace(basetype, r"^const " => "", "::" => "!")

    head * basetype * tail
end

function normalize_cxxop(op)
    replace(op, r"^\^$" => "xor",
            r"^\^=$" => "xor_eq",
            r"^bitand$" => "&",
            r"^bitor$" => "|",
            r"^compl$" => "~",
            r"^and%" => "&&",
            r"^and_eq" => "&=",
            r"^not$" => "!",
            r"^not_eq$" => "!=",
            r"^or$" => "||")
end

function doxy2jloperator(op; nargs, class, staticofclass)
    op = normalize_cxxop(op)

    jlop = if op == "*" && nargs == 1
        "Base.getindex"
    #prefix ops:
    elseif op ∈ ["~", "!", "-", "+"] && nargs==1
        "Base.:" * op
    #infix ops:
    elseif op ∈ ["-", "*", "/", "%", "&",  "|", "xor", ">>", ">>>", "<<", ">", "<", "<=", ">=",
                 "==", "!=", "<=>"]
        
        op = replace(op, "<=>" => "cmp")

        baseoverwrite = (nargs==2)
        if baseoverwrite
            if occursin(r"^[^\w]", op)
                op = "(" * op * ")" #parentheses needed for <=, >=, etc.
            end
            "Base.:" * op
        elseif staticofclass
            class * "!" * op
        else
            "(" * op * ")"
        end
    elseif op == "[]" && staticofclass
        class * "!getindex"  #unlikely case?
    elseif op == "[]" && !staticofclass
        "Base.getindex"
    else
        (staticofclass ? (class * "!") : "") * (
        replace(op, "()" => "paren",
                "+=" => "add!",
                "-=" => "sub!",
                "*=" => "mult!",
                "/=" => "fdiv!",
                "%=" => "rem!",
                "^=" => "xor!",
                "|=" => "or!",
                "&=" => "and!",
                "<<=" => "lshit!",
                ">>=" => "rshit!",
                "^" => "xor",
                "->" => "arrow",
                "->*" => "arrowstar",
                "," => "comma",
                "<=>" => "cmp",
                "--" => "dec!",
                "++" => "inc!",
                "&&"  => "logicaland",
                "||" => "logicalor",
                "=" => "assign",
                "delete[]" => "deletearray", #wrapper generation will be vetoed in next ROOT.jl releases
                "new[]" => "newarray", #wrapped generation will be vetoed in next ROOT.jl releases
                )
        )
    end
end

function doxy2jlmethod(doxymethodname; nargs, class, isstatic)
    
    staticofclass = isstatic && !isempty(class)


    doxymethodname = replace([doxymethodname],
                             "String" => "GetString",
                             "SubString" => "GetSubString",
                             "Integer" => "GetInteger",
                             "Text" => "GetText",
                             "Matrix" => "GetMatrix",
                             "Timer" => "GetTimer")[]
    
    m = match(r"(^|.*::)operator[[:space:]]*(.*)$", doxymethodname)

    return if !isnothing(m)
        cxxop = m[2]
        doxy2jloperator(cxxop; nargs = nargs, class=class, staticofclass=staticofclass)
    elseif staticofclass
        class * "!" * doxymethodname
    else
        doxymethodname
    end
end

function ensurenewline(io::MyIO, nnewlines = 1)
    if io.nchars[] > 0 #does not insert newlines if no text has been written yet
        nmissingnl = nnewlines - io.ntailnewlines[]
        nmissingnl > 0 && print(io, "\n" ^ nmissingnl)
    end
    nothing
end

function print_bullet!(io::MyIO, state)
    if isnothing(state.item_num[end])
        print(io, "- ")
    else
        print(io, state.item_num[end], ". ")
        state.item_num[end] += 1
    end
end

function func_cxxsignature(class::Union{Nothing, String},
                       funcname::String, returntype::String,
                           args::Vector{@NamedTuple{argtype::String, argname::String, defval::Union{Nothing, String}}};
                           isstatic=false, isconst=false)
    buf = IOBuffer()

    #FIXME: to uncoment when 'static' will be specified in the wrapit report
    #if !isnothing(class) !isempty(class) && isstatic
    #    print(buf, "static ")
    #end

    print(buf, doxy2cxxtype(returntype), " ")
    if !isnothing(class) !isempty(class)
        print(buf, class, "::")
    end
    print(buf, funcname, "(")
    sep = ""
    for arg in args
        print(buf, sep, doxy2cxxtype(arg.argtype))
        sep = ", "
    end
    print(buf, ")")

    #FIXME: to uncoment when 'const' will be specified in the wrapit report
    #if !isnothing(class) !isempty(class) && isconst
    #    print(buf, " const")
    #end

    String(take!(buf))
end

# return julia function name and its signature (aka prototype), (jlname, jlproto, baseoverwrite::Bool)
function func_jlproto(class::Union{Nothing, String},
                      funcname::String, returntype::String,
                      args::Vector{@NamedTuple{argtype::String, argname::String, defval::Union{Nothing, String}}};
                      isstatic=false, isconst=false)


    nargs = length(args) + (isstatic ? 0 : 1)
    jlname = doxy2jlmethod(funcname, nargs=nargs, class=class, isstatic=isstatic)
    buf = IOBuffer()
    print(buf, "(")
    sep = ""
    if !isnothing(class) && !isempty(class)
        print(buf, "this::", doxy2jltype((isconst ? "const " : "") * class * " &"))
        sep = ", "
    end

    for arg in args
        print(buf, sep, arg.argname, "::", doxy2jltype(arg.argtype))
        sep = ", "
    end
    rt = doxy2jltype(returntype, returntype=true)
    if !isempty(rt)
        print(buf, ")::", rt)
    end
    tail = String(take!(buf))

    #println(funcname, "(", join(map(x->(x.argtype * " " * x.argname), args), ", "), ")")
    #println("=> ", jlname, tail)

    (jlname=jlname, jlproto=jlname * tail) # baseoverwrite=baseoverwrite)
end

function check_start(io::MyIO, state, newline = true)
    if state.start
        state.start = false
    elseif newline
        #print(io, "\n")
        ensurenewline(io)
    end
end

function escape_for_markdown(content)
    replace(content,
            "\\/"         => "/",
            "*"           => "\\*",
            "_"           => "\\_",
            "~"           => "\\~")
end

function filter_content(content; forjulia=false)
    content = replace(content,
                      #reserved words:
                      r"\bbegin\b"  => "thebegin",
                      r"\bend\b"    => "theend",
                      r"\bmodule\b" => "themodule",
                      #for consistency with 'theend':
                      r"\bstart\b"  => "thestart",
                      r"\blocal\b"  => "local_",
                      r"\bglobal\b"  => "global_",
                      # :: are resolved in a second step, once we have the list of methods
                      # because mapping differs for static and non-static class method. In
                      # the meantime use an improbably character to spot places with a :: in
                      # C++ doc (to disting from inserted Julia ::):
                      "::"          => colonsubstitute
                      )
end

function parse_sect!(io::MyIO, e, n, state)
    #check_start(io, state)
    for e1 in eachelement(e)
        if e1.name == "title"
            ensurenewline(io, 2)
            println(io, '#' ^ n, " ", e1.content, "\n")
        else
            parse!(io, e1, state)
        end
    end
    #println(io, '#' ^ n, " ", filter_content(findfirst("//title", e).content), "\n")
    #println(io, '#' ^ n, " ", e.content, "\n")
end


function parse_anchor!(io::MyIO, e, state)
    #not included as not supported by REPL
    #FIXME: find a solution for HTML doc
    #if haskey(e, "id")
    #    print(io, "<a id=\"", e["id"], "\"></a>")
    #end

    #NO-OP
end

function parse_image!(io::MyIO, e, state)
    if get(e, "type", "") == "html"
        if haskey(e, "name")
            url = join([rstrip(refurl, '/'), e["name"]], "/")
            #print(io, "![", e["name"], "](", url, ")")
            print(io, "![", url, "](", url, ")")
        else
            print(stderr, "WARNING. Foun an XML image element without a name attribute. Element ignored.")
        end
    else
        print(stderr, "WARNING. Unknown image type found in XML file.")
    end

end

function parse_para!(io::MyIO, e, state)
    #check_start(io, state)
    #saved_nindents = io.nindents[]
    indented = false
    if state.list_depth > 0 #in a list
        # If the item of a list contains several paragraph,
        # the paragraph beyond the fist needs to be indented
        # with 4 characters
        state.item_ipara += 1
        if state.item_ipara == 1
            ensurenewline(io, 1)
            print_bullet!(io, state)
        else
            #io.nindents[] = 0
            ensurenewline(io, 2)
            #print(io, "    " ^ state.list_depth)
            indent(io)
            indented = true
        end
    else
        ensurenewline(io, 2)
    end

    for n in eachnode(e)
        parse!(io, n, state)
    end

    if indented
        unindent(io)
    end
    #io.nindents[] = saved_nindents

#    println(io, "\n")
end

function parse_listitem!(io::MyIO, e, state)
    #reset in-item paragraph count
    state.item_ipara = 0
    #ensurenewline(io) commented as already in parse_para
    for n in eachelement(e)
        parse!(io, n, state)
    end
end


function parse_itemizedlist!(io::MyIO, e, state; ordered=false)
    #increment list depth counter
    state.list_depth += 1
    push!(state.item_num, ordered ? 1 : nothing)
    ensurenewline(io, 2)
    indented = false
    # we should add an indent if we are in a nested itemized list
    # and we do not in an extra paragraph of an itemized list.
    if (state.list_depth > 1) && (state.item_ipara < 2)
        indent(io)
        indented = true
    end
    for n in eachelement(e)
        if n.name == "listitem"
            parse_listitem!(io, n, state)
        else
            println(stderr, "Unexpected itemizedlist child: ", n.name)
        end
    end
    if indented
        unindent(io)
    end
    state.list_depth -= 1
    pop!(state.item_num)
    nothing
end

function parse_ref!(io::MyIO, e, state)
    check_start(io, state, false)
    in_verbatim = state.verbatim
    in_verbatim || print(io, "[")
    for n in eachnode(e)
        parse!(io, n, state)
    end
    in_verbatim || print(io, "](@ref)")
end


function parse_computeroutput!(io::MyIO, e, state)
    check_start(io, state, false)
    print(io.base, "`")
    print(io, filter_content(e.content))
    print(io.base, "`")
end

function parse_simplesect!(io::MyIO, e, state)
    check_start(io, state, false)
    ensurenewline(io, 2)
    print(io.base, "###")
    print(io, uppercasefirst(e["kind"]), "\n\n", filter_content(e.content))
end


function parse_text!(io::MyIO, e, state)
    check_start(io, state, false)
    if state.list_depth > 0 # in a list item
        if state.item_ipara == 0 # text directly in the item without <para></para>
            state.item_ipara = 1 #text must be considered as the first paragraph
            print_bullet(io, state)
        end
    end
    print(io, filter_content(e.content))
    nothing
end

function parse_ulink!(io::MyIO, e, state)
    if haskey(e, "url")
        print(io, "[", strip(filter_content(e.content)), "](")
        saved = io.tomarkdown[]
        io.tomarkdown[] = false
        print(io, strip(e["url"]), ")")
        io.tomarkdown[] = saved
    else
        print(io, strip(filter_content(e.content)))
    end
end

function parse_heading!(io::MyIO, e, state)
    if haskey(e, "level")
        l = tryparse(Int, e["level"])
        l = max(1, min(l, 6))
        if !isnothing(l)
            print(io, "#" ^ l , " ", strip(filter_content(e.content)))
            return nothing
        end
    end
    #fallback:
    text = norm_linefeed(strip(filter_content(e.content)))
    replace!(text, "\n\n" => "**\n\n**") #ensure produced markdown is correct in such unlikely situation
    print(io.base, "**", text , "**")
    nothing
end


function parse_formula!(io::MyIO, e, state)
    check_start(io, state, false)
    if startswith(strip(filter_content(e.content)), raw"\[")
        ensurenewline(io, 2)
    end
    print(io, replace(filter_content(e.content), raw"\s*$\s*" => "``",
                      r"\\\[[\n\s]*" => "``", r"[\n\s]*\\\]" => "``\n\n"))
end

function parse_htmlonly!(io::MyIO, e, state)
    check_start(io, state)
    html = e.content
    EzXML.parsehtml(html).root.content
end


function parse_program_listing!(io::MyIO, e, state)
    ensurenewline(io, 2)
#    println(io, "```")
    indent(io)
    extra_indent = if state.list_depth > 0 && state.item_ipara == 1
        indent(io)
        true
    else
        false
    end
    saved_verbatim = state.verbatim
    state.verbatim = true
    saved_md = io.tomarkdown[]
    io.tomarkdown[] = false
    for ee in eachelement(e)
        parse!(io, ee, state)
    end
    io.tomarkdown[] = saved_md
    state.verbatim = saved_verbatim
    unindent(io)
    extra_indent && unindent(io)
    ensurenewline(io, 2)
    println(io, "(C++ version of the code)\n")
end

function parse_codeline!(io, e, state)
    ensurenewline(io)
    inner_parse!(io, e, state, "", "")
end

function parse_table!(io, e, state)
    header = Vector{String}[]
    data = Vector{String}[]
    header_filled = false
    width = 0
    for (ie1, e1) in enumerate(eachelement(e))
        e1.name == "row" || continue
        ncols = 0
        row = String[]
        tofill = data
        for e2 in eachelement(e1)
            ncols += 1
            e2.name == "entry" || continue
            io_ = MyIO(IOBuffer())
            for e3 in eachnode(e2)
                parse!(io_, e3, state)
            end
            cellcontent = strip(String(take!(io_)))
            if get(e2, "thead", "") == "yes"
                if ie1 == 1
                    tofill = header
                else
                    cellcontent = "**" * cellcontent * "**"
                end
            end
            push!(row, cellcontent)
        end
        if ie1 == 1
            width = ncols
        elseif ncols > width
            # This row is larger than previous ones!
            # Extends the previous rows
            append!.(tofill, Ref(fill("", ncols-width)))
        end
        push!(tofill, row)
    end
    ensurenewline(io)
    table = if length(header) >= 1
        pretty_table(io.base, stack(data, dims=1), alignment=:l, backend=:markdown, column_labels=header[1], line_breaks=true, allow_markdown_in_cells=true)
    else
        pretty_table(io.base, stack(data, dims=1), alignment=:l, backend=:markdown, line_breaks=true, allow_markdown_in_cells=true)
    end
    nothing
end

function parse_emphasis!(io, e, state)
    markers =  if countelements(e) == 0 && !startswith(e.content, "_") && !startswith(e.content, "*")
        ("*", "*")
    else
        "<i>", "</i>"
    end

    print(io.base, markers[1])
    for ee in eachnode(e)
        parse!(io, ee, state)
    end
    print(io.base, markers[2])
end


function parse_bold!(io, e, state)
    markers =  if countelements(e) == 0 && !startswith(e.content, "_") && !startswith(e.content, "*")
        ("**", "**")
    else
        "<b>", "</b>"
    end

    print(io.base, markers[1])
    for ee in eachnode(e)
        parse!(io, ee, state)
    end
    print(io.base, markers[2])
end

function inner_parse!(io, e, state, before="", after="")
    print(io.base, before)
    for ee in eachnode(e)
        parse!(io, ee, state)
    end
    print(io.base, after)
end

function close_codeline(io, e, state)
    ensurenewline(io)
    println(io, "```\n(C++ version of code)")
end

function parse!(io::MyIO, e, state)
    greekdict = Dict("alpha" => "α", "beta" => "β", "gamma" => "γ", "delta" => "δ", "epsilon" => "ε", "zeta" => "ζ", "eta" => "η", "theta" => "θ", "iota" => "ι", "kappa" => "κ", "lambda" => "λ", "mu" => "μ", "nu" => "ν", "xi" => "ξ", "omicron" => "ο", "pi" => "π", "rho" => "ρ", "sigma" => "σ", "tau" => "τ", "upsilon" => "υ", "phi" => "φ", "chi" => "χ", "psi" => "ψ", "omega" => "ω")

#    if !state.incodeline && state.prev_ename == "codeline" && e.name != "codeline"
#        close_codeline(io, e, state)
#    end
    
    if e.name == "text"
        parse_text!(io, e, state)
    elseif e.name == "para"
        parse_para!(io, e, state)
    elseif e.name == "itemizedlist"
        parse_itemizedlist!(io, e, state)
    elseif e.name == "orderedlist"
        parse_itemizedlist!(io, e, state; ordered = true)
    elseif e.name == "ref"
        parse_ref!(io, e, state)
    elseif e.name == "computeroutput"
        parse_computeroutput!(io, e, state)
    elseif e.name == "formula"
        parse_formula!(io, e, state)
    elseif e.name == "programlisting"
        parse_program_listing!(io, e, state)
    elseif e.name == "simplesect"
        parse_simplesect!(io, e, state)
    elseif e.name == "codeline"
        parse_codeline!(io, e, state)
    elseif e.name == "highlight" #used to highlight code keyword, no need for transcription
        for ee in eachnode(e)
            parse!(io, ee, state)
        end
    elseif e.name == "superscript"
        inner_parse!(io, e, state, "<sup>", "</sup>")
    elseif e.name == "htmlonly"
        parse_htmlonly!(io, e, state)
    elseif e.name == "subscript"
        inner_parse!(io, e, state, "<sub>", "</sub>")
    elseif e.name == "underline"
        inner_parse!(io, e, state, "<u>", "</u>")
    elseif e.name == "sp"
        print(io, " ")
    elseif e.name == "mdash"
        print(io, "—")
    elseif haskey(greekdict, e.name)
        print(io, greekdict[e.name])
    elseif e.name == "parameterlist"
        arg_descs = parse_parameter_list(e, state)
        if !isempty(arg_descs)
            println(io, "## Arguments\n")
        end
        for (name, desc) in arg_descs
            println(io, "- ", name, " ", replace(desc, "\n" => "\n    "))
        end
    elseif e.name == "hruler"
        ensurenewline(io)
        print(io, "---")
    elseif e.name == "ulink"
        parse_ulink!(io, e, state)
    elseif e.name == "heading"
        parse_heading!(io, e, state)
    elseif e.name ∈ ["verbatim", "preformatted"]
        saved_verbatim = state.verbatim
        state.verbatim = true
        ensurenewline(io)
        println(io.base, "```") #use base to prevent indentation
        for e1 in eachnode(e)
            parse!(io, e1, state)
        end
        state.verbatim = saved_verbatim
        ensurenewline(io)
        print(io.base, "``` ") #use base to prevent indentation
    elseif e.name == "anchor"
        parse_anchor!(io, e, state)
    elseif e.name == "ndash"
        print(io, "–")
    elseif e.name == "image"
        parse_image!(io, e, state)
    elseif e.name == "linebreak"
        print(io, "<br/>")
    elseif e.name == "emphasis"
        parse_emphasis!(io, e, state)
    elseif e.name == "bold"
        parse_bold!(io, e, state)
    elseif e.name == "table"
        parse_table!(io, e, state)
    elseif e.name == "lsquo"
        print(io, "'")
    elseif e.name == "rsquo"
        print(io, "'")
    elseif e.name == "blockquote"
        savedlineprefix = io.lineprefix[]
        io.lineprefix[] = ">" * savedlineprefix
        inner_parse!(io, e, state, "", "")
        io.lineprefix[] = savedlineprefix
    elseif e.name == "parblock"
        inner_parse!(io, e, state, "", "")
    elseif e.name == "details"
        inner_parse!(io, e, state, "", "")
    elseif e.name == "summary"
        inner_parse!(io, e, state, "**", "**")
    elseif e.name == "zwj"
        #to ignore, likely coming from a typo in c++ doxy docstring
    else
        m = match(r"sect(\d+)", e.name)
        if !isnothing(m)
            depth = Base.parse(Int, m[1])
            parse_sect!(io, e, depth, state)
        else
            println(stderr, "[Unknown part: ", e.name, "]")
        end
    end
#    state.prev_ename = e.name
end

function parse(io::IO, e)
    parse!(MyIO(io), e, State())
end

Base.get(node::EzXML.Node, key, default::String) = (haskey(node, key) ? node[key]::String : default)

function parse_enum(e, prefix="")
    doc = Dict{String, Any}()
    for e1 in eachelement(e)
        if e1.name == "memberdef"
            name = get(e1, "name", nothing)
            if !isnothing(name) && !startswith(doc["name"], "@")
                doc["name"] = prefix * name
            end
            doc["constants"] = Dict{String, Any}[]
            for e2 in eachelement(e1)
                constdoc = Dict{String, String}
                if e2.name == "enumvalue"
                    if haskey(e2, "name")
                        constdoc["name"] = Dict("name" => e2["name"])
                        if haskey(e2, "initializer")
                            constdoc["value"] = filter_content(e2["initializer"].content)
                        end
                    end
                elseif e2.name == "briefdescription"
                    constdoc["briefdescription"] = strip(parse_description(e2))
                elseif  e2.name == "detaileddescription"
                    constdoc["detaileddesciption"] = strip(parse_description(e2))
                end
                if !isempty(constdoc)
                    push!(doc["constants"], constdoc)
                end
            end
        end
    end
    doc
end

function parse_types_defined_in_a_class(e, class_name)
    types = Dict{String, Any}[]
    for e1 in eachelement(e)
        if e1.name == "memberdef" && haskey(e1, "kind")
            kind = e1["kind"]
            if kind == "enum"
                enum_doc = parse_enum(e1, class_name * "!")
                push!(types, enum_doc)
            end
        end
    end
    return types
end


function cxxtojulianame(cxxname)
    return replace(cxxname, "::" => "!", colonsubstitute => "!")
end


function parse_description(e)
    state = State()
    buffer = IOBuffer()
    io = MyIO(buffer)
    io.tomarkdown[] = true
    map(x->parse!(io, x, state), eachelement(e))
    String(take!(buffer))
end

# <param>
# <type>
# <ref refid="RtypesCore_8h_1afc405399e08793afdff5b4692827b2a1" kindref="member">Option_t</ref>
# *
# </type>
# <declname>axis</declname>
# <defval>"X"</defval>
# </param>
# <briefdescrip
function parse_func_param(param_node)
    argtype = ""
    argname = ""
    defval = nothing
    for e in eachnode(param_node)
        if e.name == "type"
            argtype = filter_content(e.content)
        elseif e.name == "declname"
            argname = filter_content(e.content)
        elseif e.name == "defval"
            defval = filter_content(e.content)
        end
    end
    (argtype = argtype, argname = argname, defval = defval)
end

function parse_methods(method_node, class_name; isstatic=false)
    io_ = stdout #IOBuffer()
    methods = Dict{String, Any}[]
    for method_elt in eachelement(method_node)
        if method_elt.name == "memberdef"
            isconst =  (get(method_elt, "const", "") == "yes")
            method_doc = Dict{String, Any}()
            method_doc["args"] = @NamedTuple{argtype::String, argname::String, defval::Union{Nothing, String}}[]
            for e in eachelement(method_elt)
                if e.name == "type"
                    method_doc["returntype"] = filter_content(e.content)
                elseif e.name == "param"
                    push!(method_doc["args"], parse_func_param(e))
                elseif e.name == "definition"
                    method_doc["definition"] = filter_content(e.content)
                elseif e.name == "name"
                    method_doc["name"] = filter_content(e.content)
                elseif e.name == "argsstring"
                    method_doc["argsstring"] = filter_content(e.content)
                elseif e.name == "briefdescription"
                    method_doc["briefdescription"] = strip(parse_description(e))
                elseif e.name == "detaileddescription"
                    method_doc["detaileddescription"] = strip(parse_description(e))
                end
            end #next method_elt element
            if haskey(method_doc, "name") && haskey(method_doc, "args")
                #method_doc["signature"] = method_doc["definition"] * method_doc["argsstring"]
                #isconst = occursin("const", Base.get(method_doc, "argstring", ""))
                method_doc["signature"] = func_cxxsignature(class_name, method_doc["name"],
                                                            Base.get(method_doc, "returntype", ""),
                                                            method_doc["args"],
                                                            isstatic=isstatic, isconst=isconst)
                
                method_doc["jlname"] , method_doc["jlproto"] =func_jlproto(class_name, method_doc["name"],
                                                                           Base.get(method_doc, "returntype", ""),
                                                                           method_doc["args"], isstatic=isstatic,
                                                                           isconst=isconst)

            end
            if !startswith(Base.get(method_doc, "name", ""), "~") #skip destructor
                method_doc["julianame"] = cxxtojulianame(Base.get(method_doc, "name", ""))
                push!(methods, method_doc)
            end
        end
    end
    methods
end

function parse_parameter_list(node, state)
        names = String[]
        descs = String[]
        for e1 in eachelement(node)
            if e1.name == "parameteritem"
                for e2 in eachelement(e1)
                    if e2.name == "parameternamelist"
                        for e3 in eachelement(e2)
                            if e3.name == "parametername"
                                n = "**`" * filter_content(e3.content) * "`**"
                                if haskey(e3, "direction")
                                    n *= " [" * e3["direction"] * "]"
                                end
                                push!(names, strip(n))
                            end
                        end
                    elseif e2.name == "parameterdescription"
                        io_ = MyIO(IOBuffer())
                        inner_parse!(io_, e2, copy(state), "", "")
                        push!(descs, String(take!(io_)))
#                        for e3 in eachelement(e2)
#                            if e3.name == "para"
#                                push!(descs, strip(filter_content(e3.content)))
#                            end
#                        end
                    end
                end
            end
        end
    if length(names) != length(descs)
        #This can happen if the description is common to the all the arguments.
        #Code below deals also with multiple descs (can this happen?), altough
        #the output may not ideal.
        return [(join(names, ", "), join(descs, ". "))]
    else
        return collect(zip(names, descs))
    end
end

function parse_class(class_node)
    class_doc = Dict{String, Any}()
    class_name = ""
    for e in eachelement(class_node)
        if e.name == "compoundname"
            class_name = filter_content(e.content)
            class_doc["name"] = class_name
        elseif e.name == "sectiondef"
            kind = get(e, "kind", "")
            if kind == "public-type"
                class_doc["types"] = parse_types_defined_in_a_class(e, class_name)
            elseif kind == "public-static-func"
                class_doc["static_methods"] = parse_methods(e, class_name, isstatic=true)
            elseif kind == "public-func"
                class_doc["methods"] = parse_methods(e, class_name)
            end
        elseif e.name == "briefdescription"
            class_doc["briefdescription"] = strip(parse_description(e))
        elseif  e.name == "detaileddescription"
            class_doc["detaileddescription"] = strip(parse_description(e))
        end
    end
    class_doc
end

function print_julia_doc(io::IO, module_name, doc)
    for m in Iterators.flatten((doc["methods"], doc["static_methods"]))
        println(io, "@trydoc raw\"\"\"")
        haskey(m, "jlproto") && println(io, "    ", m["jlproto"], "\n")
        haskey(m, "briefdescription") && println(io, m["briefdescription"], "\n")
        haskey(m, "detaileddescription") && print(io, m["detaileddescription"], " ")
        println("\"\"\" ", module_name, ".", m["julianame"], "\n")
    end
end

wrapdoc(docstring) = docstring
#wrapdoc(docstring) = sprint((io, x) -> print_wrapped(io, x, width=92), docstring)

function filldb(conn, inputfile)

    doc = EzXML.readxml(inputfile)

    elts = elements(doc.node)

    if length(elts) != 1 || elts[1].name != "doxygen"
        error("Unexpectd file format. Is it an XML doxygen output?")
    end

    for e in eachelement(elts[1])
        if e.name == "compounddef" && e["kind"] == "class"
            class_rcd = parse_class(e)
            method_rcds = Any[]
            if haskey(class_rcd, "methods")
                push!(method_rcds, class_rcd["methods"])
            end
            if haskey(class_rcd, "static_methods")
                push!(method_rcds, class_rcd["static_methods"])
            end
            methodlist = Set{String}()
            for m in Iterators.flatten(method_rcds)
                doc = "    " * m["jlproto"] * "\n"
                push!(methodlist, "[`" * m["jlname"] * "`](@ref)")
                if haskey(m, "briefdescription")
                    doc *= m["briefdescription"]
                end
                if haskey(m, "detaileddescription")
                    doc *= "\n" * m["detaileddescription"]
                    doc = wrapdoc(doc)
                    dbinsertmethod(conn, m["signature"], m["jlname"], m["jlproto"], class_rcd["name"], doc)
                end
            end

            #class doc:
            doc = join([get(class_rcd, "briefdescription", ""),
                        get(class_rcd, "detaileddescription", ""),
                        "Related functions: " * join(sort(collect(methodlist)), ", ")], "\n\n")
            if !isempty(doc) && haskey(class_rcd, "name")
                doc = "    ROOT." * class_rcd["name"] * "\n\n" * doc
                doc = wrapdoc(doc)
                jlname = replace(class_rcd["name"], colonsubstitute => "!")
                cxxname = replace(class_rcd["name"], colonsubstitute => "::")
                dbinserttype(conn, class_rcd["name"], jlname, doc)
            end

        else
            print(stderr, ">>>Unknown element, name = ", e.name)
            if haskey(e, "kind")
                print(stderr, ", kind = ", e["kind"])
            end
        println()
        end
    end

    nothing
end
end
