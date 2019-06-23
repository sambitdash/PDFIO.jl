export PDPage,
    pdPageGetContents,
    pdPageIsEmpty,
    pdPageGetCosObject,
    pdPageGetContentObjects,
    pdPageGetFonts,
    pdPageGetMediaBox,
    pdPageGetCropBox,
    pdPageExtractText,
    pdPageGetPageNumber

using ..Cos

abstract type PDPage end

"""
```
    pdPageGetCosObject(page::PDPage) -> CosObject
```
PDF document format is developed in two layers. A logical PDF document
information is represented over a physical file structure called COS. This method
provides the internal COS object associated with the page object.
"""
pdPageGetCosObject(page::PDPage) = page.cospage

"""
```
    pdPageGetContents(page::PDPage) -> CosObject
```
Page rendering objects are normally stored in a `CosStream` object in a PDF file.
This method provides access to the stream object.

Please refer to the PDF specification for further details.

# Example
```
julia> pdPageGetContents(page)

448 0 obj
<<
	/Length	437
	/FFilter	/FlateDecode
	/F	(/tmp/tmpZnGGFn/tmp5J60vr)
>>
stream
...
endstream
endobj
```
"""
function pdPageGetContents(page::PDPage)
    if (page.contents === CosNull)
        ref = get_page_content_ref(page)
        page.contents = get_page_contents(page, ref)
    end
    return page.contents
end

"""
```
    pdPageGetMediaBox(page::PDPage) -> CDRect{Float32}
    pdPageGetCropBox(page::PDPage) -> CDRect{Float32}
```
    Returns the media box associated with the page. See 14.11.2 PDF 1.7 Spec.
It's typically, the designated size of the paper for the page. When a crop box
is not defined, it defaults to the media box.

# Example
```
julia> pdPageGetMediaBox(page)
Rect:[0.0 0.0 595.0 792.0]

julia> pdPageGetCropBox(page)
Rect:[0.0 0.0 595.0 792.0]
```
"""
function pdPageGetMediaBox(page::PDPage)
    arr = page_find_attribute(page, cn"MediaBox")::CosArray
    return CDRect{Float32}(CDRect(arr))::CDRect{Float32}
end

function pdPageGetCropBox(page::PDPage)
    box = page_find_attribute(page, cn"CropBox")
    box === CosNull && return pdPageGetMediaBox(page)
    return CDRect{Float32}(CDRect(box))::CDRect{Float32}
end

"""
```
    pdPageIsEmpty(page::PDPage) -> Bool
```
Returns `true` when the page has no associated content object.

# Example
```
julia> pdPageIsEmpty(page)
false
```
"""
function pdPageIsEmpty(page::PDPage)
    return page.contents === CosNull && get_page_content_ref(page) === CosNull
end

"""
```
    pdPageGetContentObjects(page::PDPage) -> CosObject
```
Page rendering objects are normally stored in a `CosStream` object in a PDF file.
This method provides access to the stream object.
"""
function pdPageGetContentObjects(page::PDPage)
    page.content_objects === nothing && load_page_objects(page)
    return page.content_objects
end


"""
```
    pdPageGetFonts(page::PDPage) -> Dict{CosName, PDFont}()
```
Returns a dictionary of fonts in the page.

#Example

```
julia> pdPageGetFonts(page)
Dict{CosName,PDFIO.PD.PDFont} with 4 entries:
  /F0 => PDFont(…
  /F4 => PDFont(…
  /F8 => PDFont(…
  /F9 => PDFont(…

```
"""
function pdPageGetFonts(page::PDPage)
    cosfonts = find_resource(page, cn"Font", CosNull)
    dres = Dict{CosName, PDFont}()
    for (name, val) in cosfonts.val
        dres[name] = PDFont(page.doc, val)
    end
    return dres
end

function pdPageEvalContent(page::PDPage, state::GState=GState{:PDFIO}())
    state[:source] = page
    evalContent!(pdPageGetContentObjects(page), state)
    return state
end

"""
```
    pdPageExtractText(io::IO, page::PDPage) -> IO
```
Extracts the text from the `page`. This extraction works best for tagged PDF
files.
For PDFs not tagged, some line and word breaks will not be extracted properly.

# Example

Following code will extract the text from a full PDF file.

```
function getPDFText(src, out)
    doc = pdDocOpen(src)
    docinfo = pdDocGetInfo(doc)
    open(out, "w") do io
		npage = pdDocGetPageCount(doc)
        for i=1:npage
            page = pdDocGetPage(doc, i)
            pdPageExtractText(io, page)
        end
    end
    pdDocClose(doc)
    return docinfo
end
```
"""
function pdPageExtractText(io::IO, page::PDPage)
    state = pdPageEvalContent(page)
    show_text_layout!(io, state)
    return io
end

"""
```
    pdPageGetPageNumber(page::PDPage)
```
Returns the page number of the document page.

# Example

```
julia> pdPageGetPageNumber(page)
1
```
"""
pdPageGetPageNumber(page::PDPage) = 
    pd_doc_get_pagenum(page.doc, CosIndirectObjectRef(page.cospage))

mutable struct PDPageImpl <: PDPage
    doc::PDDocImpl
    cospage::ID{CosDict}
    contents::CosObject
    content_objects::Union{Nothing, PDPageObjectGroup}
    fonts::Dict{CosName, PDFont}
    xobjs::Dict{CosName, PDXObject}
    PDPageImpl(doc, cospage, contents) =
        new(doc, cospage, contents,
            nothing,
            Dict{CosName,PDFont}(),
            Dict{CosName,PDXObject}())
end

PDPageImpl(doc::PDDocImpl, cospage::ID{CosDict}) =
    PDPageImpl(doc, cospage, CosNull)

#=This function is added as non-exported type. PDPage may need other attributes
which will make the constructor complex. This is the default with all default
values.
=#
create_pdpage(doc::PDDocImpl, cospage::ID{CosDict}) =
    PDPageImpl(doc, cospage)
create_pdpage(doc::PDDocImpl, cospage::CosNullType) =
    throw(ErorException(E_INVALID_OBJECT))
#=
This will return a CosArray of ref or ref to a stream. This needs to be
converted to an actual stream object
=#
get_page_content_ref(page::PDPageImpl) = get(page.cospage, cn"Contents")

function get_page_contents(page::PDPageImpl, contents::CosArray)
    len = length(contents)
    arr = get(contents)
    for i = 1:len
        ref = splice!(arr, 1)
        cosstm = get_page_contents(page, ref)
        cosstm !== CosNull && push!(arr, cosstm)
    end
    stm = merge_streams(page.doc.cosDoc, contents)
    return stm
end

get_page_contents(page::PDPageImpl, contents::CosIndirectObjectRef) =
    cosDocGetObject(page.doc.cosDoc, contents)

get_page_contents(page::PDPage, obj::IDD{CosStream}) = obj

@inline function load_page_objects(page::PDPageImpl)
    contents = pdPageGetContents(page)
    page.content_objects === nothing &&
        (page.content_objects = PDPageObjectGroup())
    return load_page_objects(page, contents)
end

load_page_objects(page::PDPageImpl, stm::CosNullType) = nothing

@inline function load_page_objects(page::PDPageImpl, stm::IDD{CosStream})
    bufstm = decode(stm)
    try
        load_objects(page.content_objects, bufstm)
    finally
        util_close(bufstm)
    end
    return nothing
end

@inline function load_page_objects(page::PDPageImpl, stms::IDD{CosArray})
    stm = merge_streams(page.doc.cosDoc, stms)
    page.contents = stm
    return load_page_objects(page, stm)
end

function populate_font_encoding(page, font, fontname)
    if get(page.fums, fontname, CosNull) === CosNull
        fum = FontUnicodeMapping()
        merge_encoding!(fum, page.doc.cosDoc, font)
        page.fums[fontname] = fum
    end
end

function find_resource(page::PDPageImpl,
                       restype::CosName,
                       fontname::Union{CosName, CosNullType})
    res = CosNull
    cosdoc = page.doc.cosDoc
    pgnode = page.cospage

    while ((fontname !== CosNull && res === CosNull) ||
           (fontname === CosNull)) && pgnode !== CosNull

        resref = get(pgnode, cn"Resources")
        if resref === CosNull
            pgnode = cosDocGetObject(cosdoc, pgnode, cn"Parent")
            continue
        end
        resources = cosDocGetObject(cosdoc, resref)
        if resources === CosNull
            pgnode = cosDocGetObject(cosdoc, pgnode, cn"Parent")
            continue
        end
        ress = cosDocGetObject(cosdoc, resources, restype)
        if ress === CosNull 
            pgnode = cosDocGetObject(cosdoc, pgnode, cn"Parent")
            continue
        end
        if fontname !== CosNull
            res = cosDocGetObject(cosdoc, ress, fontname)
        else
            resdict = cosDocGetObject(cosdoc, ress, fontname)
            res === CosNull && (res = CosDict())
            for (k, v) in resdict.val
                set!(res, k, v)
            end
        end
        pgnode = cosDocGetObject(cosdoc, pgnode, cn"Parent")
    end
    return res
end

get_font(page::PDPageImpl, fontname::CosName) = 
    get!(page.fonts, fontname,
         get_pd_font!(page.doc, find_resource(page, cn"Font", fontname)))
    
get_xobject(page::PDPageImpl, xobjname::CosName) = 
    get!(page.xobjs, xobjname,
         get_pd_xobject!(page.doc,
                         find_resource(page, cn"XObject", xobjname)))

function page_find_attribute(page::PDPageImpl, resname::CosName)
    res = CosNull
    cosdoc = page.doc.cosDoc
    pgnode = page.cospage

    while pgnode !== CosNull
        res = cosDocGetObject(cosdoc, pgnode, resname)
        res !== CosNull && break
        pgnode = cosDocGetObject(cosdoc, pgnode, cn"Parent")
    end
    return res
end

get_encoded_string(s::CosString, fontname::CosNullType, page::PDPage) =
    CDTextString(s)

get_encoded_string(s::CosString, fontname::CosName, page::PDPage) =
    get_encoded_string(s, get(page.fonts, fontname, nothing))
