export PDPage,
       pdPageGetContents,
       pdPageIsEmpty,
       pdPageGetCosObject,
       pdPageGetContentObjects,
       pdPageExtractText

abstract type PDPage end

"""
```
    pdPageGetCosObject(page::PDPage) -> CosObject
```
PDF document format is developed in two layers. A logical PDF document information is
represented over a physical file structure called COS. This method provides the internal
COS object associated with the page object.
"""
pdPageGetCosObject(page::PDPage) = page.cospage

"""
```
    pdPageGetContents(page::PDPage) -> CosObject
```
Page rendering objects are normally stored in a `CosStream` object in a PDF file. This
method provides access to the stream object.

Please refer to the PDF specification for further details.
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
    pdPageIsEmpty(page::PDPage) -> Bool
```
Returns `true` when the page has no associated content object.
"""
function pdPageIsEmpty(page::PDPage)
    return page.contents === CosNull && get_page_content_ref(page) === CosNull
end

"""
```
    pdPageGetContentObjects(page::PDPage) -> CosObject
```
Page rendering objects are normally stored in a `CosStream` object in a PDF file. This
method provides access to the stream object.
"""
function pdPageGetContentObjects(page::PDPage)
    if (isnull(page.content_objects))
        load_page_objects(page)
    end
    return get(page.content_objects)
end

"""
```
    pdPageExtractText(io::IO, page::PDPage) -> IO
```
Extracts the text from the `page`. This extraction works only for tagged PDF files only.
"""
function pdPageExtractText(io::IO, page::PDPage)
    page.doc.isTagged != :tagged && throw(ErrorException(E_NOT_TAGGED_PDF))
    showtext(io, pdPageGetContentObjects(page))
    return io
end

mutable struct PDPageImpl <: PDPage
  doc::PDDocImpl
  cospage::CosObject
  contents::CosObject
  content_objects::Nullable{PDPageObjectGroup}
  PDPageImpl(doc,cospage,contents)=
    new(doc, cospage, contents, Nullable{PDPageObjectGroup}())
end

PDPageImpl(doc::PDDocImpl, cospage::CosObject) = PDPageImpl(doc, cospage,CosNull)

#=This function is added as non-exported type. PDPage may need other attributes
which will make the constructor complex. This is the default with all default
values.
=#
create_pdpage(doc::PDDocImpl, cospage::CosObject) = PDPageImpl(doc, cospage)
create_pdpage(doc::PDDocImpl, cospage::CosNullType) =
    throw(ErorException(E_INVALID_OBJECT))
#=
This will return a CosArray of ref or ref to a stream. This needs to be
converted to an actual stream object
=#
get_page_content_ref(page::PDPageImpl) = get(page.cospage, cn"Contents")

function get_page_contents(page::PDPageImpl, contents::CosArray)
  len = length(contents)
  for i = 1:len
    ref = splice!(contents, 1)
    cosstm = get_page_contents(page.doc.cosDoc,ref)
    if (cosstm != CosNull)
      push!(contents,cosstm)
    end
  end
  return contents
end

function get_page_contents(page::PDPageImpl, contents::CosIndirectObjectRef)
  return cosDocGetObject(page.doc.cosDoc, contents)
end

function get_page_contents(page::PDPage, contents::CosObject)
  return CosNull
end

function load_page_objects(page::PDPageImpl)
  stm = pdPageGetContents(page)
  if (isnull(page.content_objects))
    page.content_objects=Nullable(PDPageObjectGroup())
  end
  load_page_objects(page, stm)
end

load_page_objects(page::PDPageImpl, stm::CosNullType)=nothing

function load_page_objects(page::PDPageImpl, stm::CosObject)
  bufstm = decode(stm)
  try
    load_objects(get(page.content_objects), bufstm)
  finally
    close(bufstm)
  end
end

function load_page_objects(page::PDPageImpl, stm::CosArray)
  for s in get(stm)
    load_page_objects(page,s)
  end
end
