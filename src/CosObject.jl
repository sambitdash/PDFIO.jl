import Base:get,hash,isequal

export CosDict, CosDict, CosString, CosNumeric, CosBoolean, CosTrue, CosFalse,
       CosObject, CosNull, CosFloat, CosInt, CosArray, CosName, CosDict,
       CosIndirectObject, CosStream, get, set!

abstract CosObject

function get{T<:CosObject}(o::T)
  return o.val
end

hash(o::CosObject, h::UInt=zero(UInt)) = hash(o.val, h)

isequal(r1::CosObject, r2::CosObject) = isequal(r1.val, r2.val)


abstract CosString <: CosObject
abstract CosNumeric <: CosObject

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

type CosIndirectObject{T <: CosObject} <: CosObject
    num::Int
    gen::Int
    obj::T
end

get(o::CosIndirectObject) = get(o.obj)

immutable CosName <: CosObject
    val::String
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

"""
Set the value to object. If the object is CosNull the key is deleted.
"""
function set!(dict::CosDict, name::CosName, obj::CosObject)
  if (obj === CosNull)
    return delete!(dict,name)
  else
    dict[name] = obj
    return dict
  end
end

const CosStream_Length=CosName("Length")
const CosStream_Filter= CosName("Filter")
const CosStream_DecodeParms = CosName("DecodeParms")
const CosStream_F      = CosName("F")
const CosStream_FFilter = CosName("FFilter")
const CosStream_FDecodeParms = CosName("FDecodeParms")
const CosStream_DL=CosName("DL")


type CosStream <: CosObject
    extent::CosDict
    isInternal::Bool
    CosStream(d::CosDict,isInternal::Bool=true)=new(d,isInternal)
end

get(stm::CosStream, name::CosName) = get(stm.extent, name)

"""
Decodes the stream and provides output as an IO.
"""
get(stm::CosStream) = decode(stm)
