import Base:get,hash,isequal, convert

export CosDict, CosString, CosNumeric, CosBoolean, CosTrue, CosFalse,
       CosObject, CosNull, CosFloat, CosInt, CosArray, CosName, CosDict,
       CosIndirectObjectRef, CosStream, get, set!, convert

@compat abstract type CosObject end

function get{T<:CosObject}(o::T)
  return o.val
end

@compat abstract type CosString <: CosObject end
@compat abstract type CosNumeric <: CosObject end

immutable CosBoolean <: CosObject
    val::Bool
end

const CosTrue=CosBoolean(true)
const CosFalse=CosBoolean(false)

immutable CosNullType <: CosObject end

const CosNull=CosNullType()

immutable CosFloat <: CosNumeric
    val::Float64
end

immutable CosInt <: CosNumeric
    val::Int64
end



"""
A parsed data structure to ensure the object information is stored as an object.
This has no meaning without a associated CosDoc. When a reference object is hit
the object should be searched from the CosDoc and returned.
"""
immutable CosIndirectObjectRef <: CosObject
  val::Tuple{Int,Int}
  CosIndirectObjectRef(num::Int, gen::Int)=new((num,gen))
end

hash(o::CosIndirectObjectRef, h::UInt=zero(UInt)) = hash(o.val, h)
isequal(r1::CosIndirectObjectRef, r2::CosIndirectObjectRef) = isequal(r1.val, r2.val)

type CosIndirectObject{T <: CosObject} <: CosObject
    num::Int
    gen::Int
    obj::T
end

get(o::CosIndirectObject) = get(o.obj)

immutable CosName <: CosObject
    val::Symbol
    CosName(str::String)=new(Symbol("CosName_",str))
end

immutable CosXString <: CosString
    val::String
    CosXString(str::String)=new(str)
end

immutable CosLiteralString <: CosString
    val::String
    CosLiteralString(str::String)=new(str)
end

type CosArray <: CosObject
    val::Array{CosObject,1}
    CosArray()=new(Array{CosObject,1}())
end

type CosDict <: CosObject
    val::Dict{CosName,CosObject}
    CosDict()=new(Dict{CosName,CosObject}())
end

function get(dict::CosDict, name::CosName)
  return get(dict.val,name,CosNull)
end

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

#const CosStream_Length=CosName("Length")
#const CosStream_Filter= CosName("Filter")
#const CosStream_DecodeParms = CosName("DecodeParms")
#const CosStream_F      = CosName("F")
#const CosStream_FFilter = CosName("FFilter")
#const CosStream_FDecodeParms = CosName("FDecodeParms")
#const CosStream_DL=CosName("DL")


type CosStream <: CosObject
    extent::CosDict
    isInternal::Bool
    CosStream(d::CosDict,isInternal::Bool=true)=new(d,isInternal)
end

get(stm::CosStream, name::CosName) = get(stm.extent, name)

get(o::CosIndirectObject{CosStream}, name::CosName) = get(o.obj,name)

"""
Decodes the stream and provides output as an IO.
"""
get(stm::CosStream) = decode(stm)
