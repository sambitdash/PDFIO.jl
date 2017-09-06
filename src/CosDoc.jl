using ..Common

import Base: close

export CosDoc,
       cosDocOpen,
       cosDocClose,
       cosDocGetRoot,
       cosDocGetObject,
       cosDocGetPageNumbers

"""
```
    CosDoc
```
PDF document format is developed in two layers. A logical PDF document information is
represented over a physical file structure called COS. `CosDoc` is an access object to the
physical file structure of the PDF document. To be used for accessing PDF internal objects
from document structure when no direct API is available.

One can access any aspect of PDF using the COS level APIs alone. However, they may require
you to know the PDF specification in details and they are not the most intuititive.
"""
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

"""
```
    show(io::IO, doc::CosDoc)
```
Prints the CosDoc. The intent is to print lesser information from the structure as default
can be overwhelming flooding the REPL.
"""
function show(io::IO, doc::CosDoc)
    print(io, "\nCosDoc ==>\n")
    print(io, "\tfilepath:\t\t$(doc.filepath)\n")
    print(io, "\tsize:\t\t\t$(doc.size)\n")
    print(io, "\thasNativeXRefStm:\t $(doc.hasNativeXRefStm)\n")
    print(io, "\tTrailer dictionaries: \n")
    for t in doc.trailer
        print(io, '\t')
        print(io, t)
        print(io, '\n')
    end
end

"""
```
    cosDocClose(doc::CosDoc)
```
Reclaims all system resources consumed by the `CosDoc`. The `CosDoc` should not be used
after this method is called. `cosDocClose` only needs to be explicitly called if you have
opened the document by 'cosDocOpen'. Documents opened with `pdDocOpen` do not need to use
this method.
"""
function cosDocClose(doc::CosDocImpl)
    close(doc.ps)
    for path in doc.tmpfiles
        rm(path)
    end
end

"""
```
    cosDocOpen(filepath::String) -> CosDoc
```
Provides the access to the physical file and file structure of the PDF document. Returns a
`CosDoc` which can be subsequently used for all query into the PDF files. Remember to
release the document with `cosDocClose`, once the object is used.
"""
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

"""
```
    cosDocGetRoot(doc::CosDoc) -> CosDoc
```
The structural starting point of a PDF document. Also known as document root dictionary.
This provides details of object locations and document access methodology. This should not
be confused with the `catalog` object of the PDF document.
"""
cosDocGetRoot(doc::CosDoc) = CosNull

"""
```
    cosDocGetObject(doc::CosDoc, obj::CosObject) -> CosObject
```
PDF objects are distributed in the file and can be cross referenced from one location to
another. This is called as indirect object referencing. However, to extract actual
information one needs access to the complete object (direct object). This method provides
access to the direct object after searching for the object in the document structure. If an
indirect object reference is passed as an `obj` parameter the complete `indirect object`
(reference as well as all content of the object) are returned. A `direct object` passed to
the method is returned as is without any translation. This ensures the user does not have
to go through checking the type of the objects before accessing the contents.
"""
cosDocGetObject(doc::CosDoc, obj::CosObject) = CosNull

"""
```
    cosDocGetObject(doc::CosDoc, dict::CosObject, key::CosName) -> CosObject
```
Returns the object referenced inside the `dict` dictionary. `dict` can be a PDF dictionary
object reference or an indirect object or a direct `CosDict` object.
"""
function cosDocGetObject(doc::CosDoc, dict::CosObject, key::CosName)
    if dict isa CosIndirectObjectRef
        dict = cosDocGetObject(doc, dict)
    end
    dict === CosNull && return CosNull
    return cosDocGetObject(doc, get(dict, key))
end

function cosDocGetRoot(doc::CosDocImpl)
    root = doc.hasNativeXRefStm ? get(doc.xrefstm[1], CosName("Root")) :
                                get(doc.trailer[1], CosName("Root"))
    return cosDocGetObject(doc,root)
end

cosDocGetObject(doc::CosDocImpl, obj::CosObject) = obj

function cosDocGetObject(doc::CosDocImpl, ref::CosIndirectObjectRef)
    locObj = get(doc.xref, ref, CosObjectLoc(-1))
    locObj.loc == -1 && return CosNull
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
    (objstm === CosNull) && return CosNull
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
@inline may_have_xrefstream(doc::CosDocImpl) = (doc.version[1]>=1) && (doc.version[2]>=5)

function doc_trailer_update(ps::BufferedInputStream, doc::CosDocImpl)
    const TRAILER_REWIND=50

    seek(ps, doc.size-TRAILER_REWIND)

    if (doc.isPDF)
        locate_keyword!(ps,STARTXREF,TRAILER_REWIND) < 0 && error(E_UNEXPECTED_CHAR)
        chomp_space!(ps)
        doc.startxref = parse_number(ps).val
        chomp_space!(ps)
        #Check for EOF
        locate_keyword!(ps,EOF) != 0 && error(E_UNEXPECTED_CHAR)
    end

    if doc.isPDF
        seek(ps, doc.startxref)
        chomp_space!(ps)
        doc.hasNativeXRefStm = (may_have_xrefstream(doc) && ispdfdigit(peek(ps)))
        (doc.hasNativeXRefStm) ? read_xref_streams(ps, doc) : read_xref_tables(ps, doc)
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

function find_ntree{K, R}(fn::Function, doc::CosDoc,
                         node::CosTreeNode{K}, key::K, refdata::R)
    inrange = 0
    if (!isnull(node.range))
        inrange = (key < node.range[1]) ? -1 :
                  (key > node.range[2]) ?  1 : 0
    end
    if inrange == 0
        if isnull(node.kids) # This is the leaf
            # TBD: look into the values.
            return fn(doc, get(node.values), key, refdata)
        end
        for kid in kids
            kidobj = cosDocGetObject(doc, kid)
            kidnode = createTreeNode(K, kidobj)
            inrange, val = find_ntree(fn, doc, kidnode, key)
            if inrange == -1
                break
            elseif inrange == 0
                return (inrange,val)
            end
        end
    else
        return (inrange, nothing)
    end
    return (inrange, nothing)
end

using LabelNumerals
using RomanNumerals

const PDF_PageNumerals = [AlphaNumeral, RomanNumeral, Int]

# This may look non-intuitive but PDF pages can be the same page labels for multiple pages
# Table 159 - PDF Spec
function find_page_label(doc::CosDoc, values::Vector{Tuple{Int,CosObject}},
                         key::Int, label::String)
    prev_pageno = 0
    found = false
    lno = Nullable{LabelNumeral}()
    start = 1
    for (pageno, obj) in values
        if found
            if isnull(lno)
                return range(prev_pageno+1, pageno-prev_pageno)
            else
                ln = get(lno)
                ln < start && throw(ErrorException(E_INVALID_PAGE_NUMBER))
                found_page = prev_pageno + 1 + ln - start
                found_page <= pageno && return range(found_page, 1)
            end
            found = false
            prev_pageno = pageno
        end
        plDict = cosDocGetObject(doc, obj)
        s = get(plDict, cn"S")
        p = get(plDict, cn"P")
        st = get(plDict, cn"St")

        start = (st === CosNull) ? 1 : get(st)
        pfx = ""
        if p !== CosNull
            pfx = String(p)
        end
        if s === CosNull
            if (p === CosNull && label == "") || (label == pfx)
                prev_pageno = pageno
                found = true
                continue
            end
        else
            try
                ln = (s == cn"D") ? LabelNumeral(Int, label; prefix=pfx) :
                     (s == cn"R") ? LabelNumeral(RomanNumeral, label; prefix=pfx) :
                     (s == cn"r") ? LabelNumeral(RomanNumeral, label; prefix=pfx,
                                                 caselower=true) :
                     (s == cn"A") ? LabelNumeral(AlphaNumeral, label; prefix=pfx) :
                     (s == cn"a") ? LabelNumeral(AlphaNumeral, label; prefix=pfx,
                                                 caselower=true) :
                     throw(ErrorException(E_INVALID_PAGE_NUMBER))
                lno = Nullable(ln)
                prev_pageno = pageno
                found = true
            catch
            end
        end
    end
    found && isnull(lno) && return range(prev_pageno+1, pageno-prev_pageno)
    if (found)
        ln = get(lno)
        ln < start && throw(ErrorException(E_INVALID_PAGE_NUMBER))
        found_page = prev_pageno + 1 + ln - start
        return range(found_page, 1)
    end
    throw(ErrorException(E_INVALID_PAGE_NUMBER))
end

function get_internal_pagecount(dict::CosObject)
    mytype = get(dict, cn"Type")
    isequal(mytype, cn"Pages") && return get(get(dict, cn"Count"))
    isequal(mytype, cn"Page" ) && return 1
    error(E_INVALID_OBJECT)
end

"""
```
cosDocGetPageNumbers(doc::CosDoc, catalog::CosObject, label::AbstractString) -> Range{Int}
```
PDF utilizes two pagination schemes. An internal global page number that is maintained
serially as an integer and `PageLabel` that is shown by the viewers. Given a `label` this
method returns a `range` of valid page numbers.
"""
function cosDocGetPageNumbers(doc::CosDoc, catalog::CosObject, label::AbstractString)
    ref = get(catalog, cn"PageLabels")
    plroot = cosDocGetObject(doc, ref)
    troot = createTreeNode(Int, plroot)
    return find_ntree(find_page_label, doc, troot, -1, label)
end
