import Base: get, length, show

export CosDict, CosString, CosXString, CosLiteralString, CosNumeric,
    CosBoolean, CosTrue, CosFalse, CosObject, CosNull, CosNullType,
    CosFloat, CosInt, CosArray, CosName, CosDict, CosIndirectObjectRef,
    CosStream, set!, @cn_str, createTreeNode, CosTreeNode, CosIndirectObject,
    CosDictType, IDD, IDDRef, IDDN, IDDNRef, ID, IDRef, IDN, IDNRef, showref

"""
```
    CosObject
```

PDF is a structured document format with lots of internal data
structures like dictionaries, arrays, trees. `CosObject` is the
interface to access these objects and get detailed access to the
objects and gather additional information. Although, defined in the
COS layer, objects of these type are returned from almost all the
APIs. Hence, the objects have a separate significance whether you need
to use the `Cos` layer or not. Below is the object hierarchy.

```
CosObject                           Abstract
    CosNull                         Value (CosNullType)
CosString                           Abstract
CosName                             Concrete
CosNumeric                          Abstract
    CosInt                          Concrete
    CosFloat                        Concrete
CosBoolean                          Concrete
    CosTrue                         Value (CosBoolean)
    CosFalse                        Value (CosBoolean)
CosDict                             Concrete
CosArray                            Concrete
CosStream                           Concrete (always wrapped as an indirect object)
CosIndirectObjectRef                Concrete (only useful when CosDoc is available)
```

*Note*: As a reader API you may not need to instantiate any of `CosObject` types.
They are normally populated as a result of parsing a PDF file. 
"""
abstract type CosObject end

"""
```
    get(o::CosObject) -> val
    get(o::CosIndirectObjectRef) -> (objnum, gennum)
```
"""
get(o::CosObject) = o.val

"""
```
    CosString
```
Abstract type that represents a PDF string. In PDF objects are mere byte representations.
They translate to actual text strings by application of fonts and associated encodings.
"""
abstract type CosString <: CosObject end

get(o::T) where {T <: CosString} = copy(o.val)
"""
```
    CosNumeric
```
Abstract type for numeric objects. The objects can be an integer [`CosInt`](@ref) or float
[`CosFloat`](@ref).
"""
abstract type CosNumeric <: CosObject end

"""
```
    CosBoolean
```
A boolean object in PDF which is either a `CosTrue` or `CosFalse`
"""
struct CosBoolean <: CosObject
    val::Bool
end

const CosTrue=CosBoolean(true)
const CosFalse=CosBoolean(false)

struct CosNullType <: CosObject end

"""
```
    CosNull
```
PDF representation of a `null` object. Can be applied to [`CosObject`](@ref)
of any type.
"""
const CosNull=CosNullType()

"""
```
    CosFloat
```
A numeric float data type.
"""
struct CosFloat <: CosNumeric
    val::Float32
end

"""
```
    CosInt
```
An integer in PDF document.
"""
struct CosInt <: CosNumeric
    val::Int
end

"""
```
    CosIndirectObjectRef
```
A parsed data structure to ensure the object information is stored as an object.
This has no meaning without a associated CosDoc. When a reference object is hit
the object should be searched from the CosDoc and returned.
"""
struct CosIndirectObjectRef <: CosObject
    val::Tuple{Int, Int}
    CosIndirectObjectRef(num::Int, gen::Int)=new((num, gen))
end

mutable struct CosIndirectObject{T <: CosObject} <: CosObject
    num::Int
    gen::Int
    obj::T
end

CosIndirectObjectRef(obj::CosIndirectObject) =
    CosIndirectObjectRef(obj.num, obj.gen)

get(o::CosIndirectObject) = get(o.obj)

# Aliases for certain commonly used Union types
# IDD     = Indirect and Direct
# IDDRef  = Indirect, Direct and Reference
# IDDN    = Indirect, Direct, Null
# IDDNRef = Indirect, Direct, Null, Refence

const IDD{X}     = Union{X, CosIndirectObject{X}}
const IDDRef{X}  = Union{X, CosIndirectObject{X}, CosIndirectObjectRef}
const IDDN{X}    = Union{X, CosIndirectObject{X}, CosNullType}
const IDDNRef{X} = Union{X, CosIndirectObject{X}, CosNullType,
                         CosIndirectObjectRef}
const ID{X}      = CosIndirectObject{X}
const IDRef{X}   = Union{CosIndirectObject{X}, CosIndirectObjectRef}
const IDN{X}     = Union{CosIndirectObject{X}, CosNullType}
const IDNRef{X}  = Union{CosIndirectObject{X}, CosNullType, CosIndirectObjectRef}

"""
```
    CosName
```
Name objects are symbols used in PDF documents.
"""
struct CosName <: CosObject
    val::Symbol
    CosName(str::AbstractString) = new(Symbol("CosName_",str))
end

"""
```
    @cn_str(str) -> CosName
```
A string decorator for easier instantiation of a [`CosName`](@ref)

*Example*:
```
julia> cn"Name"
/Name
```
"""
macro cn_str(str)
    return CosName(str)
end

#=
```
    CosXString
```
Concrete representation of a [`CosString`](@ref) object. The underlying data is
represented as hexadecimal characters in ASCII.
=#
struct CosXString <: CosString
    val::Vector{UInt8}
    CosXString(arr::Vector{UInt8})=new(arr)
end

#=
```
    CosLiteralString
```
Concrete representation of a [`CosString`](@ref) object. The underlying data is
represented by byte representations without any encoding.
=#
struct CosLiteralString <: CosString
    val::Vector{UInt8}
    CosLiteralString(arr::Vector{UInt8}) = new(arr)
end

function CosLiteralString(str::AbstractString)
    buf = IOBuffer()
    for c in str
        print(buf, Char(c))
    end
    CosLiteralString(take!(buf))
end

"""
```
    CosArray
```
An array in a PDF file. The objects can be any combination of [`CosObject`](@ref).
"""
mutable struct CosArray <: CosObject
    val::Vector{CosObject}
    CosArray(arr::Vector{CosObject}) = new(arr)
    CosArray() = new(Vector{CosObject}())
end

"""
```
    get(o::CosArray, isNative=false) -> Vector{CosObject}
```
An array in a PDF file. The objects can be any combination of
[`CosObject`](@ref).

`isNative = true` will return the underlying native object inside the `CosArray`
by invoking get method on it.

# Example
```
julia> a = CosArray(CosObject[CosInt(1), CosFloat(2f0), CosInt(3), CosFloat(4f0)])
[1 2.0 3 4.0 ]

julia> get(a)
4-element Array{CosObject,1}:
 1  
 2.0
 3  
 4.0

julia> get(a, true)
4-element Array{Real,1}:
 1    
 2.0f0
 3    
 4.0f0
```
"""
get(o::CosArray, isNative=false) = isNative ? map(get, o.val) : o.val

get(o::CosIndirectObject{CosArray}, isNative=false) = get(o.obj, isNative)
"""
```
    length(o::CosArray) -> Int
```
Number of elements in `CosArray`

# Example
```
julia> a = CosArray(CosObject[CosInt(1), CosFloat(2f0),
                              CosInt(3), CosFloat(4f0)])
[1 2.0 3 4.0 ]

julia> length(a)
4
```
"""
length(o::CosArray) = length(o.val)
length(o::ID{CosArray}) = length(o.obj)

Base.getindex(o::CosArray, i::Int) = o.val[i]
Base.getindex(o::ID{CosArray}, i::Int) = getindex(o.obj, i)

"""
```
    CosDict
```
Name value pair of a PDF objects. The object is very similar to the `Dict`
object. The `key` has to be of a [`CosName`](@ref) type.
"""
mutable struct CosDict <: CosObject
    val::Dict{CosName, CosObject}
    CosDict()=new(Dict{CosName, CosObject}())
end

const CosDictType = IDD{CosDict}

"""
```
    get(dict::CosDict, name::CosName, defval::T = CosNull) where T ->
                                                            Union{CosObject, T}
    get(stm::CosStream, name::CosName, defval::T = CosNull) where T ->
                                                            Union{CosObject, T}
```
Returns the value as a [`CosObject`](@ref) for the key `name` or the `defval`
provided.

In case of `CosStream` objects the data is collected from the extent dictionary.

# Example
```
julia> get(catalog, cn"Version")
null

julia> get(catalog, cn"Version", cn"1.4")
/1.4

julia> get(catalog, cn"Version", "1.4")
"1.4"
```
"""
get(dict::CosDict, name::CosName, defval::T = CosNull) where T =
    get(dict.val, name, defval)

"""
```
    set!(dict::CosDict, name::CosName, obj::CosObject) -> CosDict

    set!(stm::CosStream, name::CosName, obj::CosObject) -> CosStream

```
Sets the value on a dictionary object. Setting a `CosNull` object deletes the
object from the dictionary.

In case of `CosStream` objects the data is added to the extent dictionary.

# Example
```
julia> set!(catalog, cn"Version", cn"1.4")

julia> <<
...
/Version /1.4
...
>>
```
"""
function set!(dict::CosDict, name::CosName, obj::CosObject)
    if (obj === CosNull)
        delete!(dict.val, name)
    else
        dict.val[name] = obj
    end
    return dict
end

"""
```
    CosStream
```
A stream object in a PDF. Stream objects have an `extends` disctionary, followed
by binary data.
"""
mutable struct CosStream <: CosObject
    extent::CosDict
    isInternal::Bool
    CosStream(d::CosDict, isInternal::Bool=true) = new(d, isInternal)
end

get(stm::CosStream, name::CosName, defval::T = CosNull) where T =
    get(stm.extent, name, defval)

set!(stm::CosStream, name::CosName, obj::CosObject)=
    (set!(stm.extent, name, obj); stm)

"""
```
    get(stm::CosStream) -> IO
```
Decodes the stream and provides output as an `IO`.

# Example
```
julia> stm

448 0 obj
<<
	/FFilter	/FlateDecode
	/F	(/tmp/tmpIyGPhL/tmp9hwwaG)
	/Length	437
>>
stream
...
endstream
endobj

julia> io = get(stm)
IOBuffer(data=UInt8[...], readable=true, writable=true, ...)

```
"""
get(stm::CosStream) = decode(stm)

mutable struct CosObjectStream <: CosObject
    stm::CosStream
    n::Int
    first::Int
    oids::Vector{Int}
    oloc::Vector{Int}
    populated::Bool
    function CosObjectStream(s::CosStream)
        n = get(s, cn"N")
        @assert n != CosNull
        first = get(s, cn"First")
        @assert first !== CosNull
        n_n = get(n)
        first_n = get(first)
        oids = zeros(Int, n_n)
        oloc = zeros(Int, n_n)
        # cosStreamRemoveFilters(s)
        # read_object_info_from_stm(s, oids, oloc, n_n, first_n)
        new(s, n_n, first_n,oids, oloc, false)
    end
end

get(os::CosObjectStream, name::CosName, defval::T = CosNull) where T =
    get(os.stm, name, defval)

set!(os::CosObjectStream, name::CosName, obj::CosObject)=
    (set!(os.stm, name, obj); os)

get(os::CosObjectStream) = get(os.stm)

get(o::Union{CosIndirectObject{CosDict},
             CosIndirectObject{CosStream},
             CosIndirectObject{CosObjectStream}},
    name::CosName, defval::T = CosNull) where T =
        get(o.obj, name, defval)

set!(os::Union{CosIndirectObject{CosDict},
               CosIndirectObject{CosStream},
               CosIndirectObject{CosObjectStream}},
     name::CosName, obj::CosObject) =
         (set!(os.obj, name, obj); os)


#=
mutable struct CosXRefStream <: CosObject
  stm::CosStream
  isDecoded::Bool
  function CosXRefStream(s::CosStream, isDecoded::Bool=false)
      new(s, isDecoded)
  end
end

get(os::CosXRefStream, name::CosName) = get(os.stm, name)

get(os::CosIndirectObject{CosXRefStream}, name::CosName) = get(os.obj,name)

set!(os::CosXRefStream, name::CosName, obj::CosObject)=
    set!(os.stm, name, obj)

set!(os::CosIndirectObject{CosXRefStream}, name::CosName, obj::CosObject)=
    set!(os.obj,name,obj)

get(os::CosXRefStream) = get(os.stm)
=#

#=
Can be a Number Tree or a Name Tree.

`kids`: is `null` in case of a leaf node
`range`: is `null` in case of a root node
`values`: is `null` in case of an intermediate node

Intent: faster loookup without needing to load the complete tree structure.
Hence, the tree will not be loaded on full scan.
=#
mutable struct CosTreeNode{K <: Union{Int, String}}
    values::Union{Nothing, Vector{Tuple{K, CosObject}}}
    kids::Union{Nothing, Vector{CosIndirectObjectRef}}
    range::Union{Nothing, Tuple{K, K}}
    function CosTreeNode{K}() where {K <: Union{Int, String}}
        new(nothing, nothing, nothing)
    end
end

# If K is Int, it's a number tree else it's a String which is a name tree
function createTreeNode(::Type{K}, dict::IDD{CosDict}) where K
    range = get(dict, cn"Limits")
    kids  = get(dict, cn"Kids")
    node = CosTreeNode{K}()
    if (range !== CosNull)
        r = get(range, true)
        node.range = (K(r[1]), K(r[2]))
    end
    if (kids !== CosNull)
        node.kids = get(kids)
    end
    return populate_values(node, dict)
end

function populate_values(node::CosTreeNode{Int}, dict::IDD{CosDict})
    nums = get(dict, cn"Nums")
    if (nums !== CosNull)
        v = get(nums)
        values = [(get(v[2i-1]), v[2i]) for i=1:div(length(v), 2)]
        node.values = values
    end
    return node
end

function populate_values(node::CosTreeNode{String}, dict::IDD{CosDict})
    names = get(dict, cn"Names")
    if (names !== CosNull)
        v = get(names, false) #true => v[2i] is Tuple{Int} => error
        values = [(String(v[2i-1]), v[2i]) for i=1:div(length(v), 2)]
        node.values = values
    end
    return node
end

# All show methods

show(io::IO, o::CosObject) = print(io, o.val)

showref(io::IO, o::CosObject) = show(io, o)

show(io::IO, o::CosNullType) = print(io, "null")

show(io::IO, o::CosName) = print(io, "/", String(o))

show(io::IO, o::CosXString) =  print(io, "<", String(copy(o.val)), ">")

function show(io::IO, o::CosLiteralString)
    print(io, '(')
    for b in o.val
        c = Char(b)
        if isprint(c)
            print(io, c)
        else
            print(io, '\\')
            print(io, string(b, base=8, pad=3))
        end
    end
    print(io, ')')
end

function show(io::IO, o::CosArray)
  print(io, '[')
  for obj in o.val
    showref(io, obj)
    print(io, ' ')
  end
  print(io, ']')
end

function show(io::IO, o::CosDict)
    print(io, "<<\n")
    for (k,v) in o.val
        print(io, '\t')
        show(io, k)
        print(io, '\t')
        showref(io, v)
        println(io, "")
    end
    print(io, ">>")
end

show(io::IO, stm::CosStream) =
  (show(io, stm.extent); print(io, "\nstream\n...\nendstream"))

show(io::IO, os::CosObjectStream) = show(io, os.stm)

show(io::IO, o::CosIndirectObjectRef) = print(io, o.val[1], ' ', o.val[2], " R")

showref(io::IO, o::CosIndirectObject) = print(io, o.num, ' ', o.gen, " R")

function show(io::IO, o::CosIndirectObject)
    println(io, "")
    println(io, o.num, ' ', o.gen, " obj")
    print(io, o.obj)
    println(io, "\nendobj\n")
end

#=
```
    CosComment
```
A comment object in PDF which is normally ignored as a whitespace.
=#
struct CosComment <: CosObject
    val::String
end

CosComment(barr::Vector{UInt8}) = CosComment(String(Char.(barr)))

show(io::IO, os::CosComment) = print(io, '%', os.val)

