export PDDoc,
       pdDocOpen,
       pdDocClose,
       pdDocGetCatalog,
       pdDocGetNamesDict,
       pdDocGetInfo,
       pdDocGetCosDoc,
       pdDocGetPage,
       pdDocGetPageCount,
       pdDocGetPageRange,
       pdDocHasPageLabels,
       pdDocGetOutline

using ..Common

"""
```
    PDDoc
```
An in memory representation of a PDF document. Once created this type has to be
used to access a PDF document.
"""
abstract type PDDoc end

"""
```
    pdDocOpen(filepath::AbstractString) -> PDDoc
```
Opens a PDF document and provides the PDDoc document object for subsequent query
into the PDF file. `filepath` is the path to the PDF file in the relative or
absolute path format.

Remember to release the document with `pdDocClose`, once the object is used.
"""
function pdDocOpen(filepath::AbstractString)
    doc = PDDocImpl(filepath)
    update_page_tree(doc)
    update_structure_tree!(doc)
    return doc
end

"""
```
    pdDocClose(doc::PDDoc, num::Int) -> PDDoc
```
Reclaim the resources associated with a `PDDoc` object. Once called the `PDDoc`
object cannot be further used.
"""
function pdDocClose(doc::PDDoc)
  cosDocClose(doc.cosDoc)
end

"""
```
    pdDocGetPageCount(doc::PDDoc) -> Int
```
Returns the number of pages associated with the document.
"""
function pdDocGetPageCount(doc::PDDoc)
  return Cos.get_internal_pagecount(doc.pages)
end

"""
```
    pdDocGetCatalog(doc::PDDoc) -> CosObject
```
`Catalog` is considered the topmost level object in  PDF document that is
subsequently used to traverse and extract information from a PDF document. To be
used for accessing PDF internal objects from document structure when no direct
API is available.
"""
pdDocGetCatalog(doc::PDDoc) = doc.catalog

"""
```
    pdDocGetCosDoc(doc::PDDoc) -> CosDoc
```
PDF document format is developed in two layers. A logical PDF document
information is represented over a physical file structure called COS. `CosDoc` is
an access object to the physical file structure of the PDF document. To be used
for accessing PDF internal objects from document structure when no direct API is
available.

One can access any aspect of PDF using the COS level APIs alone. However, they
may require you to know the PDF specification in details and it is not the most
intuititive.
"""
pdDocGetCosDoc(doc::PDDoc)= doc.cosDoc

"""
```
    pdDocGetPage(doc::PDDoc, num::Int) -> PDPage
    pdDocGetPage(doc::PDDoc, ref::CosIndirectObjectRef) -> PDPage
```
Given a document absolute page number or object reference, provides the
associated page object.
"""
pdDocGetPage


"""
```
    pdDocGetPageRange(doc::PDDoc, nums::AbstractRange{Int}) -> Vector{PDPage}
    pdDocGetPageRange(doc::PDDoc, label::AbstractString) -> Vector{PDPage}
```
Given a range of page numbers or a label returns an array of pages associated
with it.
For a detailed explanation on page labels, refer to the method
`pdDocHasPageLabels`.
"""
function pdDocGetPageRange(doc::PDDoc, nums::AbstractRange{Int})
    pages = []
    for i in nums
        push!(pages, pdDocGetPage(doc, i))
    end
    return pages
end

function pdDocGetPageRange(doc::PDDoc, label::AbstractString)
    catalog = pdDocGetCatalog(doc)
    pr = cosDocGetPageNumbers(doc.cosDoc, catalog, label)
    return pdDocGetPageRange(doc, pr)
end

"""
```
    pdDocHasPageLabels(doc::PDDoc) -> Bool
```
Returns `true` if the document has page labels defined.

As per PDF Specification 1.7 Section 12.4.2, a document may optionally define page
labels (PDF 1.3) to identifyeach page visually on the screen or in print. Page labels
and page indices need not coincide: the indices shallbe fixed, running consecutively
through the document starting from 0 for the first page, but the labels may be
specified in any way that is appropriate for the particular document.
"""
function pdDocHasPageLabels(doc::PDDoc)
    catalog = pdDocGetCatalog(doc)
    return get(catalog, cn"PageLabels") !== CosNull
end

"""
```
    pdDocGetInfo(doc::PDDoc) -> Dict
```
Given a PDF document provides the document information available in the `Document
Info` dictionary. The information typically includes *creation date, modification
date, author, creator* used etc. However, all information content are not
mandatory. Hence, all information needed may not be available in a document.
If document does not have Info dictionary at all this method returns `nothing`.

Please refer to the PDF specification for further details.
"""
function pdDocGetInfo(doc::PDDoc)
    obj = cosDocGetInfo(doc.cosDoc)
    obj === CosNull && return nothing
    dInfo = Dict{CDTextString, Union{CDTextString, CDDate, CosObject}}()
    for (key, val) in get(obj)
        skey = CDTextString(key)
        try
            dInfo[skey] = (skey == "CreationDate") ||
                          (skey == "ModDate") ? CDDate(val) :
                          (skey == "Trapped") ? val : CDTextString(val)
        catch
            # no op: we skip the key that cannot be properly decoded
        end
    end
    return dInfo
end

"""
```
    pdDocGetNamesDict(doc::PDDoc) -> CosObject
```
Some information in PDF is stored as name and value pairs not essentially a
dictionary. They are all aggregated and can be accessed from one `names`
dictionary object in the document catalog. This method provides access to such
values in a PDF file. Not all PDF document may have a names dictionary. In such
cases, a `CosNull` object may be returned.

Please refer to the PDF specification for further details.
"""
function pdDocGetNamesDict(doc::PDDoc)
    catalog = pdDocGetCatalog(doc)
    ref = get(catalog, CosName("Names"))
    obj = cosDocGetObject(doc.cosDoc, ref)
end

"""
```
    pdDocGetOutline(doc::PDDoc) -> PDOutline
```
Given a PDF document provides the document Outline (Table of Contents) available
in the `Document Catalog` dictionary. If document does not have Outline, this
method returns `nothing`.

A PDF document may contain a document outline that the conforming reader may
display on the screen, allowing the user to navigate interactively from one part
of the document to another. The outline consists of a tree-structured hierarchy
of outline items (sometimes called bookmarks), which serve as a visual table of
contents to display the document’s structure to the user. The user may
interactively open and close individual items by clicking them with the mouse.
When an item is open, its immediate children in the hierarchy shall become
visible on the screen; each child may in turn be open or closed, selectively
revealing or hiding further parts of the hierarchy. When an item is closed, all
of its descendants in the hierarchy shall be hidden. Clicking the text of any
visible item activates the item, causing the conforming reader to jump to a
destination or trigger an action associated with the item. - Section 12.3.3 -
Document management — Portable document format — Part 1: PDF 1.7
"""
function pdDocGetOutline(doc::PDDoc)
    catalog = pdDocGetCatalog(doc)
    cosDoc = pdDocGetCosDoc(doc)
    tocobj = cosDocGetObject(cosDoc, catalog, cn"Outlines")
    tocobj === nothing && return nothing
    return PDOutline(doc, tocobj)
end
