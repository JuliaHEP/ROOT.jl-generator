module ROOTdocDB
using SQLite

export Conn, dbinsertmethod, dbinserttype, dbgetmethoddoc, register_wrapped_type, register_wrapped_method,
    methods_missing_doc, methods_with_doc, wrapped_methods, jldocs, typealiases, fixcolons, dbgetmethodsofclass

#character for temporary substitution of :: from the orignal c++ comments
const colonsubstitute = "⯐"

struct Conn
    db::SQLite.DB
    insertmethod_stmt::SQLite.Stmt
    inserttype_stmt::SQLite.Stmt
    getdoc_stmt::SQLite.Stmt
    getmethodsofclass_stmt::SQLite.Stmt
    insert_wrapped_method_stmt::SQLite.Stmt
    insert_wrapped_type_stmt::SQLite.Stmt
end

"""
   Conn(filename)

Open database file. It creates the required tables if missing.
"""
function Conn(filename)
    db = SQLite.DB(filename)
    DBInterface.execute(db, """CREATE TABLE IF NOT EXISTS method_doc (
cxxsignature TEXT PRIMARY KEY,
jlname TEXT,
jlsignature TEXT,
class TEXT,
jldoc TEXT
)
""")

    DBInterface.execute(db, """CREATE TABLE IF NOT EXISTS type_doc (
cxxsignature TEXT PRIMARY KEY,
jlname TEXT,
jldoc TEXT
)
""")

    DBInterface.execute(db, """CREATE TABLE IF NOT EXISTS wrapped_methods (
cxxsignature TEXT PRIMARY KEY
)
""")

    DBInterface.execute(db, """CREATE TABLE IF NOT EXISTS wrapped_types (
cxxsignature TEXT PRIMARY KEY
)
""")
    
    insertmethod_stmt = SQLite.Stmt(db, "REPLACE INTO method_doc VALUES(:cxxsignature, :jlname, :jlsignature, :class, :jldoc)")
    inserttype_stmt = SQLite.Stmt(db, "REPLACE INTO type_doc VALUES(:cxxsignature, :jlname, :jldoc)")
    getdoc_stmt = SQLite.Stmt(db, "SELECT jlsignature, jldoc FROM method_doc WHERE cxxsignature = :cxxsignature")
    getmethodsofclass_stmt = SQLite.Stmt(db, """SELECT jlsignature 
    FROM method_doc
    WHERE class = :class
    AND cxxsignature IN (SELECT cxxsignature FROM wrapped_methods) ORDER BY jlname""")
    insert_wrapped_method_stmt = SQLite.Stmt(db, "REPLACE INTO wrapped_methods VALUES(:cxxsignature)")
    insert_wrapped_type_stmt = SQLite.Stmt(db, "REPLACE INTO wrapped_types VALUES(:cxxsignature)")
    Conn(db, insertmethod_stmt, inserttype_stmt, getdoc_stmt, getmethodsofclass_stmt, insert_wrapped_method_stmt, insert_wrapped_type_stmt#=, insert_jlname_stmt=#)
end

"""
   dbinsertmethod(conn, cxxsignature, jlsignature, class, jldoc)

Insert in the database `conn` the documentation entry for the method with signature (c++ prototype) `cxxsignature`. If the entry already exists, it is replaced.
"""
function dbinsertmethod(conn, cxxsignature, jlname, jlsignature, class, jldoc)
    DBInterface.execute(conn.insertmethod_stmt, cxxsignature = cxxsignature, jlname=jlname, jlsignature=jlsignature, class=class, jldoc=jldoc)
    nothing
end

"""
   dbinsertmethodtype(conn, cxxsignature, jlname, doc)

Insert in the database `conn` the documentation entry for the type `jlnam`. If the entry already exists, it is replaced.
"""
function dbinserttype(conn, cxxsignature, jlname, jldoc)
    DBInterface.execute(conn.inserttype_stmt, cxxsignature=cxxsignature, jlname=jlname, jldoc=jldoc)
    nothing
end

#function dbinsertname(conn, name)
#    DBInterface.execute(conn.insert_jlname_stmt, name=name)
#    nothing
#end

"""
   dbgetmethoddoc(conn, cxxsignature)

Retrieve from the database `conn` the documentation entry for the method with signature (c++ prototype) `cxxsignature`. Return a tuple with the julia method name and its documentation if the entry is found, `nothing` otherwise.
"""
function dbgetmethoddoc(conn, cxxsignature)::Union{Nothing, Tuple{2, String}}
    result = DBInterface.execute(conn.getdoc_stmt, cxxsignature = cxxsignature)
    if length(result) == 0
        nothing
    else
        (result[1][1], result[1][2])
    end
end


function dbgetmethodsofclass(conn, classname)
    result = DBInterface.execute(conn.getmethodsofclass_stmt, class=classname)
    [row[1] for row in result]
end

"""
    register_wrapped_type(conn, signature)

Add a type in the list of wrapped types in the database.
"""
register_wrapped_type(conn, signature) = DBInterface.execute(conn.insert_wrapped_type_stmt, cxxsignature = signature)


"""
    register_wrapped_method(conn, signature)

Add a type in the list of wrapped methods in the database.
"""
register_wrapped_method(conn, signature) = SQLite.execute(conn.insert_wrapped_method_stmt, cxxsignature = signature)


function methods_missing_doc(conn)
    result = DBInterface.execute(conn.db, """
    SELECT wm.cxxsignature
    FROM wrapped_methods wm
        LEFT JOIN method_doc md ON wm.cxxsignature = md.cxxsignature
    WHERE md.cxxsignature IS NULL
    """)
    [ row[1] for row in result]
end

"""
    methods_with_doc(conn, iswrapped = false)

Retrieve from the database `conn`, the list of methods with a documentation. If `iswrapped` is `true`, then only methods registered with a wrapper are included in the list.
"""
function methods_with_doc(conn; iswrapped = false)
    result = if iswrapped
        DBInterface.execute(conn.db, """
        SELECT wm.cxxsignature
        FROM wrapped_methods wm
        INNER JOIN method_doc md ON wm.cxxsignature = md.cxxsignature
""")
    else
        DBInterface.execute(conn.db, """
    SELECT cxxsignature
    FROM method_doc
    """)
    end

    [ row[1] for row in result]
end

function types_missing_doc(conn)
    result = DBInterface.execute(conn.db, """
    SELECT wm.cxxsignature
    FROM wrapped_types wm
        LEFT JOIN type_doc md ON wm.cxxsignature = md.cxxsignature
    WHERE md.cxxsignature IS NULL
    """)
    [ row[1] for row in result]
end

"""
    types_with_doc(conn, iswrapped = false)

Retrieve from the database `conn`, the list of types with a documentation. If `iswrapped` is `true`, then only types registered with a wrapper are included in the list.
"""
function types_with_doc(conn; iswrapped = false)
    result = if iswrapped
        DBInterface.execute(conn.db, """
        SELECT wt.cxxsignature
        FROM wrapped_types wt
        INNER JOIN type_doc td ON wt.cxxsignature = td.cxxsignature
""")
    else
        DBInterface.execute(conn.db, """
    SELECT cxxsignature
    FROM type_doc
    """)
    end

    [ row[1] for row in result]
end


"""
    jldocs(conn)

Retrieve from the database `conn`, the documentation of wrapped methods and types.
"""
function jldocs(conn)
    methoddocs = DBInterface.execute(conn.db, """
        SELECT t1.cxxsignature, t1.jlsignature, t1.jldoc
        FROM method_doc t1
        INNER JOIN wrapped_methods t2 ON t1.cxxsignature = t2.cxxsignature
""")
    
    typedocs = DBInterface.execute(conn.db, """
        SELECT t1.cxxsignature, t1.jlname, t1.jldoc
        FROM type_doc t1
        INNER JOIN wrapped_types t2 ON t1.cxxsignature = t2.cxxsignature
""")

    ([ (row[1], row[2], row[3]) for row in typedocs ],
     [ (row[1], row[2], row[3]) for row in methoddocs ])
end


"""
    typesaliases()

Generate Julia code to define type aliases used in the documenation of the ROOT wrappers.
"""
function typealiases()
    raw"""
# Reexport from CxxWrap:
export CxxPtr, ConstCxxPtr, CxxRef, ConstCxxRef

# Export type aliases used in the documentation
export ByCopy, ByConstRef1, ByRef1, ByConstPtr1, ByPtr1, ByConstRef2, ByRef2, ByConstPtr2, ByPtr2

# Wrapper of @doc that catches exception
macro trydoc(doc, entity)
    sentity = string(entity)
    quote
        try
            @doc $(esc(doc)) $entity
        catch e
            if haskey(ENV, "ROOTDOC_DEBUG")
               @warn("Error when setting documentation for " * $sentity * ": " * sprint(showerror, e) * ".")
            end
        end
    end
end

# Wrapper to catch error on expr resulting in an unexpected dispatch
macro trydoc(expr)
    sexpr = string(expr)
    quote
        if haskey(ENV, "ROOTDOC_DEBUG")
           @warn("Error when setting documentation for " * $sexpr * ".")
        end
    end
end

######################################################################
# Type aliases used in the documentation

\"\"\"
    ByCopy{T}

Alias for Union{T, ConstCxxRef{T}, CxxRef{T}}. This type is used in the Julia wrappers of C++ functions for arguments of C++ class type passed by copy. It allows to pass an object allocated with a contructor (e.g., T()) or an object reference returnes by another C++ function wrapper.
\"\"\"
const ByCopy{T} = Union{T, CxxRef{T}, ConstCxxRef{T}}

\"\"\"
    ByConstRef1{T}

Alias for Union{T, ConstCxxRef{<:T}, CxxRef{<:T}}. This type is used in the Julia wrappers of C++ functions for arguments of C++ class type passed by reference. It allows to pass an object allocated with a contructor (e.g., T()) or an object reference returnes by another C++ function wrapper.
\"\"\"
const ByConstRef1{T} = Union{T, CxxRef{<:T}, ConstCxxRef{<:T}}


\"\"\"
    ByRef1{T}

Alias for `Union{T, ConstCxxRef{<:T}, CxxRef{<:T}}`. This type is used in the Julia wrappers of C++ functions for arguments of C++ class type passed by reference. It allows to pass an object allocated with a contructor (e.g., T()) or an object reference returnes by another C++ function wrapper.
\"\"\"
const ByRef1{T} = Union{T, ConstCxxRef{<:T}, CxxRef{<:T}}

\"\"\"
    ByConstPtr1{T}

Alias for `Union{Ptr{Nothing}, ConstCxxPtr{<:T}, CxxPtr{<:T}}`. This type is used in the Julia wrappers of C++ functions for arguments of C++ class type  passed by pointer. It allows to pass `C_NULL` or an object pointer, returned by another C++ function wrapper created with `ConstCxxPtr(obj)` with `obj::T`.
\"\"\"
const ByConstPtr1{T} = Union{Ptr{Nothing}, ConstCxxPtr{<:T}, CxxPtr{<:T}}

\"\"\"
    ByPtr1{T}

Alias for `Union{CxxPtr{<:T}, Ptr{Nothing}}`. This type is used in the Julia wrappers of C++ functions for arguments passed by pointer. It allows to pass C_NULL or an object pointer, returned by another C++ function wrapper created with `CxxPtr(obj)` with obj::T..
\"\"\"
const ByPtr1{T} = Union{CxxPtr{<:T}, Ptr{Nothing}}

\"\"\"
    ByConstRef2{T}

Alias for Union{T, Ref{T}}, with `ConstCxxRef` and `CxxRef` defined in the `CxxWrap` module. This type is used in the Julia wrappers of C++ functions for arguments of isbit type passed by reference.
\"\"\"
const ByConstRef2{T} = Union{T, Ref{T}}

\"\"\"
    ByRef2{T}

Alias for Union{T, Ptr{T}, CxxPtr{T}, CxxRef{T}, Base.RefValue{T}, Array{T}}, with `ConstCxxRef` and `CxxRef` defined in the `CxxWrap` module. This type is used in the Julia wrappers of C++ functions for arguments of isbit type passed by reference.
\"\"\"
const ByRef2{T} = Union{T, Ptr{T}, CxxPtr{T}, CxxRef{T}, Base.RefValue{T}, Array{T}}


\"\"\"
    ByConstPtr2{T}

Alias for  Union{Ptr{Nothing}, Ref{T}, Array{T}}, with ConstCxxPtr and CxxPtr defined in the CxxWrap module. This type is used in the Julia wrappers of C++ functions for arguments of C++ class type  passed by pointer. It allows to pass an object allocated with a contructor (e.g., T()) or an object reference returnes by another C++ function wrapper.
\"\"\"
const ByConstPtr2{T} = Union{Ptr{Nothing}, Ref{T}, Array{T}}

\"\"\"
    ByPtr2{T}

Alias for `Union{T, Ptr{T}, Ptr{Nothing}, CxxPtr{T}, CxxRef{T}, Base.RefValue{T}, Array{T}}`. This type is used in the Julia wrappers of C++ functions for arguments passed by pointer. It allows to pass an object pointer returned by another C++ function wrapper or C_NULL. To pass an object instance obj, uses `CxxWrap.CxxPtr(obj)`.
\"\"\"
const ByPtr2{T} = Union{T, Ptr{T}, Ptr{Nothing}, CxxPtr{T}, CxxRef{T}, Base.RefValue{T}, Array{T}}

#
######################################################################
"""
end



"""
    wrapped_methods(conn)

Retrieve from the database `conn`, the list of methods with a documentation. If `iswrapped` is `true`, then only methods registered with a wrapper are included in the list.
"""
function wrapped_methods(conn; jlname=false)
    result = DBInterface.execute(conn.db, """
        SELECT """ * (jlname ? "jlname" : "cxxsignature") * """
        FROM wrapped_methods
""")
    
    [ row[1] for row in result]
end

"""
    wrapped_types(conn)

Retrieve from the database `conn`, the list of methods with a documentation. If `iswrapped` is `true`, then only methods registered with a wrapper are included in the list.
"""
function wrapped_types(conn; jlname=false)
    result = DBInterface.execute(conn.db, """
        SELECT  """ * (jlname ? "jlname" : "cxxsignature") * """
        FROM wrapped_types
""")
    
    [ row[1] for row in result]
end

function colonfilter(content, jlnames)
    pos = 1
    buf = IOBuffer()
    while pos < length(content)
        range = findfirst(Regex("(([^\\s]+)$colonsubstitute)+([^\\s])+"), content[pos:end])
        if isnothing(range)
            print(buf, content[pos:end])
            break
        else
            range = (pos + range.start - 1) : (pos + range.stop - 1)
        end
        tomodify = content[range]
        words = split(tomodify, colonsubstitute)
        ns = if length(words) > 3
            words[1:(end-2)]
        else
            String[]
        end
        candidate1 = join(words, "!")
        candidate2 = join(vcat(ns, [words[end]]), "!")
        new = if candidate2 ∈ jlnames
            candidate2
        else
            candidate1
        end
        print(buf, content[pos:(range.start-1)], new)
        pos = range.stop + 1
    end
    oldcontent = content
    rc = if pos > 1
        content = String(take!(buf))
        true
    else
        false
    end
#    print(stderr, oldcontent, " => ", content, " (pos=", pos, ")")
    (content, rc)
end   

function fixcolons(conn)
    result = DBInterface.execute(conn.db, """
    SELECT jlname FROM type_doc
    WHERE jlname LIKE '%!%'
    UNION ALL
    SELECT jlname FROM method_doc
    WHERE jlname LIKE '%!%';
    """)
    jlnames = [ row[1] for row in result ]

    updatedoc_stmt = [SQLite.Stmt(conn.db, "UPDATE method_doc SET jldoc=:jldoc where cxxsignature=:cxxsignature"),
                      SQLite.Stmt(conn.db, "UPDATE type_doc SET jldoc=:jldoc where cxxsignature=:cxxsignature")]
    
    listdoc_stmt = [SQLite.Stmt(conn.db, "SELECT cxxsignature, jldoc FROM method_doc"),
                    SQLite.Stmt(conn.db, "SELECT cxxsignature, jldoc FROM type_doc")]

    listdoccnt_stmt = [SQLite.Stmt(conn.db, "SELECT count(*) FROM method_doc"),
                    SQLite.Stmt(conn.db, "SELECT count(*) FROM type_doc")]

    nrows = mapreduce(x->first(DBInterface.execute(x))[1], +, listdoccnt_stmt)
    step = max(nrows ÷ 20, 1)

    idoc = 0
    for itable in 1:2
        docs = DBInterface.execute(listdoc_stmt[itable])
        for (cxxsignature, jldoc) in docs
            idoc += 1
            if (idoc % step) == 1
                println(stderr, idoc, "/" , nrows)
            end
            (jldoc, modified) = colonfilter(jldoc, jlnames)
            if modified
                DBInterface.execute(updatedoc_stmt[itable], jldoc=jldoc, cxxsignature=cxxsignature)
            end
        end
    end
end

end

