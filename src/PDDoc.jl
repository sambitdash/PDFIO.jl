export PDDoc,
       pdDocOpen,
       pdDocClose,
       pdDocGetCatalog,
       pdDocGetNamesDict,
       pdDocGetInfo,
       pdDocGetCosDoc,
       pdDocGetPage,
       pdDocGetPageCount,
       pdDocGetPageRange

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
    pdDocGetInfo(doc::PDDoc) -> Dict
```
Given a PDF document provides the document information available in the `Document
Info` dictionary. The information typically includes *creation date, modification
date, author, creator* used etc. However, all information content are not
mandatory. Hence, all information needed may not be available in a document.

Please refer to the PDF specification for further details.
"""
function pdDocGetInfo(doc::PDDoc)
    obj = cosDocGetInfo(doc.cosDoc)
    dInfo = Dict{CDTextString, Union{CDTextString, CDDate}}()
    if obj != CosNull
        for (key, val) in get(obj)
            skey = CDTextString(key)
            dInfo[skey] = (skey == "CreationDate") || (skey == "ModDate") ?
                          CDDate(val) : CDTextString(val)
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
