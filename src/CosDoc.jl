using ..Common

import Base: close

export CosDoc,
       cosDocOpen,
       cosDocClose,
       cosDocGetRoot,
       cosDocGetObject

abstract type CosDoc end

mutable struct CosDocImpl <: CosDoc
  filepath::String
  size::Int
  io::IOStream
  ps::BufferedInputStream{IOStream}
  header::String
  startxref::Int
  version::Tuple{Int,Int}
  xref::Dict{CosIndirectObjectRef, CosObjectLoc}
  trailer::Vector{CosDict}
  xrefstm::Vector{CosIndirectObject{CosStream}}
  tmpfiles::Vector{AbstractString}
  isPDF::Bool
  hasNativeXRefStm::Bool
  function CosDocImpl(fp::String)
    io = util_open(fp,"r")
    sz = filesize(fp)
    ps = BufferedInputStream(io)
    new(fp,sz,io,ps,"",0,(0,0),Dict{CosIndirectObjectRef, CosObjectLoc}(),
        [], [], [], false, false)
  end
end

function cosDocClose(doc::CosDocImpl)
  close(doc.ps)
  for path in doc.tmpfiles
    rm(path)
  end
end

function cosDocOpen(fp::String)
  doc = CosDocImpl(abspath(fp));
  ps = doc.ps
  h = read_header(ps)
  doc.version = (h[1], h[2])
  doc.header = String(h[3])

  doc.isPDF = (doc.header == "PDF")

  doc_trailer_update(ps,doc)

  return doc
end

cosDocGetRoot(doc::CosDoc) = CosNull
cosDocGetObject(doc::CosDoc, obj::CosObject) = CosNull


function cosDocGetRoot(doc::CosDocImpl)

  root = (doc.hasNativeXRefStm) ?
          get(doc.xrefstm[1], CosName("Root")) :
          get(doc.trailer[1], CosName("Root"))
  return cosDocGetObject(doc,root)
end

cosDocGetObject(doc::CosDocImpl, obj::CosObject)=obj

function cosDocGetObject(doc::CosDocImpl, ref::CosIndirectObjectRef)
  locObj = doc.xref[ref]
  return cosDocGetObject(doc, locObj.stm, ref, locObj)
end

function cosDocGetObject(doc::CosDocImpl, stm::CosNullType,
  ref::CosIndirectObjectRef, locObj::CosObjectLoc)
  if (locObj.obj == CosNull)
    seek(doc.ps,locObj.loc)
    locObj.obj = parse_indirect_obj(doc.ps, doc.xref)
    attach_object(doc, locObj.obj)
  end
  return locObj.obj
end

function cosDocGetObject(doc::CosDocImpl, stmref::CosIndirectObjectRef,
  ref::CosIndirectObjectRef, locObj::CosObjectLoc)
  objstm = cosDocGetObject(doc, stmref)
  if (locObj.obj == CosNull)
    locObj.obj = cosObjectStreamGetObject(objstm, ref, locObj.loc)
    attach_object(doc, locObj.obj)
  end
  return locObj.obj
end

function read_header(ps)
  skipv(ps,PERCENT)
  b = UInt8[]
  c = advance!(ps)
  while(c != MINUS_SIGN)
    push!(b,c)
    c=advance!(ps)
  end
  major = advance!(ps)
  if ispdfdigit(major)
      major -= DIGIT_ZERO
  else
      error(E_BAD_HEADER)
  end
  skipv(ps,PERIOD)
  minor = advance!(ps)

  if ispdfdigit(minor)
      minor -= DIGIT_ZERO
  else
      error(E_BAD_HEADER)
  end
  return [major,minor,b]
end


function read_trailer(ps::BufferedInputStream, lookahead::Int)
  if locate_keyword!(ps,TRAILER,lookahead) < 0
      error(E_UNEXPECTED_CHAR)
  end
  #Check for EOL
  chomp_eol!(ps)
  skipv(ps,LESS_THAN)
  skipv(ps,LESS_THAN)

  dict = parse_dict(ps)
  chomp_space!(ps)

  return dict
end

#PDF-Version >= 1.5
@inline may_have_xrefstream(doc::CosDocImpl)=
  (doc.version[1]>=1)&&(doc.version[2]>=5)

function doc_trailer_update(ps::BufferedInputStream, doc::CosDocImpl)
  const TRAILER_REWIND=50

  seek(ps, doc.size-TRAILER_REWIND)

  if (doc.isPDF)
    if locate_keyword!(ps,STARTXREF,TRAILER_REWIND) < 0
      error(E_UNEXPECTED_CHAR)
    end
    chomp_space!(ps)
    doc.startxref = parse_number(ps).val
    chomp_space!(ps)
    #Check for EOF
    if locate_keyword!(ps,EOF) != 0
        error(E_UNEXPECTED_CHAR)
    end
  end

  if doc.isPDF
    seek(ps, doc.startxref)
    doc.hasNativeXRefStm=(may_have_xrefstream(doc) && ispdfdigit(peek(ps)))

    if (doc.hasNativeXRefStm)
      read_xref_streams(ps, doc)
    else
      read_xref_tables(ps, doc)
    end
  end
end

attach_object(doc::CosDocImpl, obj::CosObject)=nothing

attach_object(doc::CosDocImpl, objstm::CosIndirectObject{CosObjectStream})=
  attach_object(doc,objstm.obj.stm)

attach_object(doc::CosDocImpl, indstm::CosIndirectObject{CosStream})=
  attach_object(doc,indstm.obj)

function attach_object(doc::CosDocImpl, stm::CosStream)
  tmpfile = get(get(stm,  CosName("F")))
  push!(doc.tmpfiles, String(tmpfile))
  return nothing
end

function attach_xref_stream(doc::CosDocImpl,
  xrefstm::CosIndirectObject{CosStream})
  attach_object(doc, xrefstm)
  push!(doc.xrefstm, xrefstm)
end

function read_xref_streams(ps::BufferedInputStream, doc::CosDocImpl)
  found = false
  while(true)
    xrefstm = parse_indirect_obj(ps, doc.xref)

    if (!found)
      if (get(xrefstm,  CosName("Root")) == CosNull)
        error(E_BAD_TRAILER)
      else
        attach_xref_stream(doc, xrefstm)
      end
      found = true
    else
      attach_xref_stream(doc, xrefstm)
    end
    read_xref_stream(xrefstm, doc)

    prev = get(xrefstm,  CosName("Prev"))
    if (prev == CosNull)
      break
    end
    seek(ps, get(prev))
  end
end

function read_xref_tables(ps::BufferedInputStream, doc::CosDocImpl)
  found = false
  while(true)
    read_xref_table(ps,doc)
    trailer = read_trailer(ps, length(TRAILER))

    if (!found)
      if (get(trailer,  CosName("Root")) == CosNull)
        error(E_BAD_TRAILER)
      else
        push!(doc.trailer, trailer)
      end
      found = true
    else
      push!(doc.trailer, trailer)
    end
    #Hybrid case
    loc = get(trailer,  CosName("XRefStm"))
    if (loc != CosNull)
      seek(ps, get(loc))
      xrefstm = parse_indirect_obj(ps, doc.xref)
      attach_object(doc, xrefstm)
      read_xref_stream(xrefstm,doc)
    end


    prev = get(trailer, CosName("Prev"))
    if (prev == CosNull)
      break
    end
    seek(ps, get(prev))
  end
end

# The xref stream may be accessed later. There is no point encrypting this data
#Ideal will be to remove the filter.
function read_xref_stream(xrefstm::CosObject, doc::CosDocImpl)
  return read_xref_stream(xrefstm, doc.xref)
end

function read_xref_table(ps::BufferedInputStream, doc::CosDocImpl)
    skipv(ps, XREF)
    chomp_eol!(ps)


    while (true)
        if !ispdfdigit(peek(ps))
            break
        end
        oid = parse_unsignednumber(ps).val
        n_entry = parse_unsignednumber(ps).val

        for i=1:n_entry
            v = UInt8[]

            for j = 1:20
                push!(v, advance!(ps))
            end

            if (v[18] != LATIN_F)
                ref = CosIndirectObjectRef(oid, parse(Int,String(v[12:16])))

                if !haskey(doc.xref,ref)
                    doc.xref[ref] = CosObjectLoc(parse(Int,String(v[1:10])))
                end
            end

            oid +=1
        end
    end
    return doc.xref
end
