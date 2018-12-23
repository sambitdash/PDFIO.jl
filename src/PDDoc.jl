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
```
Given a document absolute page number, provides the associated page object.
"""
pdDocGetPage


"""
```
    pdDocGetPageRange(doc::PDDoc, nums::AbstractRange{Int}) -> Vector{PDPage}
    pdDocGetPageRange(doc::PDDoc, label::AbstractString) -> Vector{PDPage}
```
Given a range of page numbers or a label returns an array of pages associated
with it.
For a detailed explanation on page labels, refer to the method `pdDocHasPageLabels`.
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
            # no op: we skipp the key that cannot be properly decoded
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
    pdDocGetOutline(doc::PDDoc; depth::Number = Inf, compact::Bool = false, add_index::Bool = false) -> PDOutline
```
Given a PDF document provides the document Outline (Table of Contents)
available in the `Document Catalog` dictionary.
Returned object is an array of either `PDOutlineItem` or `PDOutline` items.
Nested `PDOutline` is allways preceded by `PDOutlineItem` and contain its sub-sections.
First element of `PDOutline` array is allways `PDOutlineItem`.

`PDOutlineItem` represent outline item and is a dictionairy object with following keys:
- `:Title` - outline displayed title (`CDTextString`), always present
- `:Level` - nesting level of the item (`Int`), optional, not present in level 1 items or if `:Index` key is present
- `:Index` - inxedes of the item in Outline structure (`NTuple`), optional, not present if `:Level` key is present.
             If index is (a,b,c) the item can be referred as outline[a][b][c], where outline is a object returned by this function.
- `:Expanded` - weather child items should be expanded by the GUI viewer by default (`Bool`), optional
- `:Style` - the style which should be applied to item by the GUI viewer (`Int`) - refer to PDF specification, optional.
- `:PageRef` - indirect reference to respective page (`CosIndirectObjectRef`) - use with other API functions eg. `cosDocGetObject`, present if not in compact mode
- `:PageNo` - absulute number of respective page (`Int`), present if not in compact mode
- `:PageLabel` - displayable label of respective page (`LabelNumeral` - can be casted to `String`), optional.

Optional, named parameters:
- `depth` - limits retrieved items to certain nesting level (0 for root chapters), default: no limit
- `compact` - if `true`, only `:Title` and `:Level` or `:Index` are retrived - works substantially faster, default: `false`
- `add_index` - if `true`, `:Index` key is placed instead of `:Level` - with minimal overhead, default: `false`

If document does not have Outline, this method returns `nothing`.

Note: This method extracts most important information from PDF Outline entry.
There are more information stored in those PDF structures. Use low level functions of this library to extract them if necessary.
"""
function pdDocGetOutline(doc::PDDoc;
        depth::Number = Inf,
        compact::Bool = false,
        add_index::Bool = false
        )
    catalog = pdDocGetCatalog(doc)
    cosDoc = pdDocGetCosDoc(doc)
    toc_ref = get(catalog, cn"Outlines")
    toc_ref === CosNull && return nothing
    toc = cosDocGetObject(cosDoc, toc_ref)
    toc_first_ref = get(toc, cn"First")
    toc_last_ref = get(toc, cn"Last")
    index = add_index ? [1] : Vector{Int}()
    if compact
        PD.get_outline_node_compact(cosDoc, toc_first_ref, toc_last_ref, 0, depth, index)
    else
        pgmap = PD.get_pageref_to_pageno_map(doc)
        PD.get_outline_node_full(cosDoc, toc_first_ref, toc_last_ref, 0, depth, index, pgmap)
    end
end
