import Base:get, length, show

export CosDict, CosString, CosNumeric, CosBoolean, CosTrue, CosFalse,
       CosObject, CosNull, CosNullType,CosFloat, CosInt, CosArray, CosName,
       CosDict, CosIndirectObjectRef, CosStream, get, set!, @cn_str,
       createTreeNode, CosTreeNode

"""
```
    CosObject
```
PDF is a structured document format with lots of internal data structures like
dictionaries, arrays, trees. `CosObject` is the interface to access these objects and get
detailed access to the objects and gather additional information. Although, defined in the
COS layer, objects of these type are returned from almost all the APIs. Hence, the objects
have a separate significance whether you need to use the `Cos` layer or not. Below is the
object hierarchy.

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
"""
abstract type CosObject end

@inline get{T<:CosObject}(o::T)=o.val

"""
```
    CosString
```
"""
abstract type CosString <: CosObject end
"""
```
    CosNumeric
```
"""
abstract type CosNumeric <: CosObject end

"""
```
    CosBoolean
```
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
"""
const CosNull=CosNullType()

"""
```
    CosFloat
```
"""
struct CosFloat <: CosNumeric
    val::Float64
end

"""
```
    CosFloat
```
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
  val::Tuple{Int,Int}
  CosIndirectObjectRef(num::Int, gen::Int)=new((num,gen))
end

mutable struct CosIndirectObject{T <: CosObject} <: CosObject
  num::Int
  gen::Int
  obj::T
end

get(o::CosIndirectObject) = get(o.obj)

"""
```
    CosName
```
"""
struct CosName <: CosObject
    val::Symbol
    CosName(str::String)=new(Symbol("CosName_",str))
end

"""
```
    @cn_str
```
"""
macro cn_str(str)
    return CosName(str)
end

"""
```
    CosXString
```
"""
struct CosXString <: CosString
  val::Vector{UInt8}
  CosXString(arr::Vector{UInt8})=new(arr)
end

"""
```
    CosLiteralString
```
"""
struct CosLiteralString <: CosString
    val::Vector{UInt8}
    CosLiteralString(arr::Vector{UInt8})=new(arr)
end

CosLiteralString(str::AbstractString)=CosLiteralString(transcode(UInt8,str))

"""
```
    CosArray
```
"""
mutable struct CosArray <: CosObject
    val::Array{CosObject,1}
    function CosArray(arr::Array{T,1} where {T<:CosObject})
      val = Array{CosObject,1}()
      for v in arr
        push!(val,v)
      end
      new(val)
    end
    CosArray()=new(Array{CosObject,1}())
end

get(o::CosArray, isNative=false)=isNative ? map((x)->get(x),o.val) : o.val
length(o::CosArray)=length(o.val)

"""
```
    CosDict
```
"""
mutable struct CosDict <: CosObject
    val::Dict{CosName,CosObject}
    CosDict()=new(Dict{CosName,CosObject}())
end

get(dict::CosDict, name::CosName)=get(dict.val,name,CosNull)

get(o::CosIndirectObject{CosDict}, name::CosName) = get(o.obj, name)

"""
Set the value to object. If the object is CosNull the key is deleted.
"""
function set!(dict::CosDict, name::CosName, obj::CosObject)
  if (obj === CosNull)
    return delete!(dict.val,name)
  else
    dict.val[name] = obj
    return dict
  end
end

set!(o::CosIndirectObject{CosDict}, name::CosName, obj::CosObject) =
            set!(o.obj, name, obj)

"""
```
    CosStream
```
"""
mutable struct CosStream <: CosObject
    extent::CosDict
    isInternal::Bool
    CosStream(d::CosDict,isInternal::Bool=true)=new(d,isInternal)
end

get(stm::CosStream, name::CosName) = get(stm.extent, name)

get(o::CosIndirectObject{CosStream}, name::CosName) = get(o.obj,name)

set!(stm::CosStream, name::CosName, obj::CosObject)=
    set!(stm.extent, name, obj)

set!(o::CosIndirectObject{CosStream}, name::CosName, obj::CosObject)=
    set!(o.obj,name,obj)

"""
Decodes the stream and provides output as an BufferedInputStream.
"""
get(stm::CosStream) = decode(stm)

"""
```
    CosObjectStream
```
"""
mutable struct CosObjectStream <: CosObject
  stm::CosStream
  n::Int
  first::Int
  oids::Vector{Int}
  oloc::Vector{Int}
  function CosObjectStream(s::CosStream)
    n = get(s, CosName("N"))
    @assert n != CosNull
    first = get(s, CosName("First"))
    @assert first != CosNull
    cosStreamRemoveFilters(s)
    n_n = get(n)
    first_n = get(first)
    oids = Vector{Int}(n_n)
    oloc = Vector{Int}(n_n)
    read_object_info_from_stm(s, oids, oloc, n_n, first_n)
    new(s, n_n, first_n,oids, oloc)
  end
end

get(os::CosObjectStream, name::CosName) = get(os.stm, name)

get(os::CosIndirectObject{CosObjectStream}, name::CosName) = get(os.obj,name)

set!(os::CosObjectStream, name::CosName, obj::CosObject)=
    set!(os.stm, name, obj)

set!(os::CosIndirectObject{CosObjectStream}, name::CosName, obj::CosObject)=
    set!(os.obj,name,obj)

get(os::CosObjectStream) = get(os.stm)

"""
```
    CosObjectStream
```
"""
mutable struct CosXRefStream<: CosObject
  stm::CosStream
  isDecoded::Bool
  function CosXRefStream(s::CosStream,isDecoded::Bool=false)
    new(s,isDecoded)
  end
end

get(os::CosXRefStream, name::CosName) = get(os.stm, name)

get(os::CosIndirectObject{CosXRefStream}, name::CosName) = get(os.obj,name)

set!(os::CosXRefStream, name::CosName, obj::CosObject)=
    set!(os.stm, name, obj)

set!(os::CosIndirectObject{CosXRefStream}, name::CosName, obj::CosObject)=
    set!(os.obj,name,obj)

get(os::CosXRefStream) = get(os.stm)

"""
Can be a Number Tree or a Name Tree.

`kids`: is `null` in case of a leaf node
`range`: is `null` in case of a root node
`values`: is `null` in case of an intermediate node

Intent: faster loookup without needing to load the complete tree structure. Hence, the tree
will not be loaded on full scan.
"""
mutable struct CosTreeNode{K <: Union{Int, String}}
    values::Nullable{Vector{Tuple{K,CosObject}}}
    kids::Nullable{Vector{CosIndirectObjectRef}}
    range::Nullable{Tuple{K,K}}
    function CosTreeNode{K}() where {K <: Union{Int, String}}
        new(Nullable{Vector{Tuple{K,CosObject}}}(),
            Nullable{Vector{CosIndirectObjectRef}}(),
            Nullable{Tuple{K,K}}())
    end
end

# If K is Int, it's a number tree else it's a String which is a name tree
function createTreeNode{K}(::Type{K}, dict::CosObject)
    range = get(dict, CosName("Limits"))
    kids  = get(dict, CosName("Kids"))
    node = CosTreeNode{K}()
    if (range !== CosNull)
        r = get(range, true)
        node.range = Nullable((r[1],r[2]))
    end
    if (kids !== CosNull)
        ks = get(kids)
        node.kids = Nullable(ks)
    end
    return populate_values(node, dict)
end

function populate_values(node::CosTreeNode{Int}, dict::CosObject)
    nums = get(dict, CosName("Nums"))
    if (nums !== CosNull)
        v = get(nums)
        values = [(get(v[2i-1]),v[2i]) for i=1:div(length(v),2)]
        node.values = Nullable(values)
    end
    return node
end

function populate_values(node::CosTreeNode{String}, dict::CosObject)
    names = get(dict, CosName("Names"))
    if (names !== CosNull)
        v = get(names, true)
        values = [(get(v[2i-1]),v[2i]) for i=1:div(length(v),2)]
        node.values = Nullable(values)
    end
    return node
end

# All show methods

show(io::IO, o::CosObject) = print(io, o.val)

showref(io::IO, o::CosObject) = show(io, o)

show(io::IO, o::CosNullType) = print(io, "null")

show(io::IO, o::CosName) = @printf io "/%s" String(o)

show(io::IO, o::CosXString) =  @printf io "%s" "<"*String(copy(o.val))*">"

show(io::IO, o::CosLiteralString) = @printf io "%s" "("*String(copy(o.val))*")"

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
  (show(io, stm.extent); print(io, "stream\n...\nendstream\n"))

show(io::IO, os::CosObjectStream) = show(io, os.stm)

show(io::IO, o::CosIndirectObjectRef) = @printf io "%d %d R" o.val[1] o.val[2]

showref(io::IO, o::CosIndirectObject) = @printf io "%d %d R" o.num o.gen

show(io::IO, o::CosIndirectObject) =
  (@printf io "\n%d %d obj\n" o.num o.gen; show(io, o.obj); println(io, "\nendobj\n"))
