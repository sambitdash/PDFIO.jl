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
       pdDocGetPageLabel,
       pdDocGetOutline,
       pdDocHasSignature,
       pdDocValidateSignatures

using ..Common, ..Cos

"""
```
    PDDoc
```
An in memory representation of a PDF document. Mostly, used as an opaque handle
to be passed on to other methods.

See [`pdDocOpen`](@ref).
"""
abstract type PDDoc end

"""
```
    pdDocOpen(filepath::AbstractString) -> PDDoc
```
Opens a PDF document and provides the PDDoc document object for subsequent query
into the PDF file. `filepath` is the path to the PDF file in the relative or
absolute path format.

Remember to release the document with `pdDocClose`, once the object is no longer
required. Although `doc` has certain members, it should normally considered as
an opaque handle. 

# Example
```
julia> doc = pdDocOpen("test/PDFTest-0.0.4/stillhq/3.pdf")

PDDoc ==>

CosDoc ==>
	filepath:		/home/sambit/.julia/dev/PDFIO/test/PDFTest-0.0.4/stillhq/3.pdf
	size:			817945
	hasNativeXRefStm:	 false
	Trailer dictionaries: 
	<<
	/Info	146 0 R
	/Prev	814755
	/Size	163
	/Root	154 0 R
	/ID	[<2ff783c9846ab546bd49f709cb7be307> <2ff783c9846ab546bd49f709cb7be307> ]
>>
	<<
	/Size	153
	/ID	[<2ff783c9846ab546bd49f709cb7be307> <2ff783c9846ab546bd49f709cb7be307> ]
>>

Catalog:
154 0 obj
<<
	/Type	/Catalog
	/Pages	152 0 R
>>
endobj

isTagged: none
```
"""
function pdDocOpen(filepath::AbstractString)
    doc = PDDocImpl(filepath)
    update_page_tree(doc)
    update_structure_tree!(doc)
    return doc
end

"""
```
    pdDocClose(doc::PDDoc, num::Int) -> Nothing
```
Reclaim the resources associated with a `PDDoc` object. Once called the `PDDoc`
object cannot be further used.

# Example
```
julia> pdDocClose(doc)
```
"""
function pdDocClose(doc::PDDoc)
  cosDocClose(doc.cosDoc)
end

"""
```
    pdDocGetPageCount(doc::PDDoc) -> Int
```
Returns the number of pages associated with the document.

# Example
```
julia> pdDocGetPageCount(doc)
30
```
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

# Example
```
julia> pdDocGetCatalog(doc)

154 0 obj
<<
	/Pages	152 0 R
	/Type	/Catalog
>>
endobj
```
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

# Example
```
julia> cosdoc = pdDocGetCosDoc(doc)

CosDoc ==>
	filepath:		/home/sambit/.julia/dev/PDFIO/test/PDFTest-0.0.4/stillhq/3.pdf
	size:			817945
	hasNativeXRefStm:	 false
	Trailer dictionaries: 
	<<
	/ID	[<2ff783c9846ab546bd49f709cb7be307> <2ff783c9846ab546bd49f709cb7be307> ]
	/Size	163
	/Prev	814755
	/Info	146 0 R
	/Root	154 0 R
>>
	<<
	/ID	[<2ff783c9846ab546bd49f709cb7be307> <2ff783c9846ab546bd49f709cb7be307> ]
	/Size	153
>>
```
"""
pdDocGetCosDoc(doc::PDDoc)= doc.cosDoc

"""
```
    pdDocGetPage(doc::PDDoc, num::Int) -> PDPage
    pdDocGetPage(doc::PDDoc, ref::CosIndirectObjectRef) -> PDPage
```
Given a document absolute page number or object reference, provides the
associated page object.

# Example

```
julia> page = pdDocGetPage(doc, 1)
PDFIO.PD.PDPageImpl(...)
julia> page = pdDocGetPage(doc, CosIndirectObjectRef(155, 0))
PDFIO.PD.PDPageImpl(...)
```
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

# Example

```
julia> pages = pdDocGetPageRange(doc, 1:4);

julia> typeof(pages)
Array{PDFIO.PD.PDPageImpl,1}

julia> length(pages)
4
```
"""
function pdDocGetPageRange(doc::PDDoc, nums::AbstractRange{Int})
    pages = PDPageImpl[]
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

# Example

```
julia> PDFIO.PD.pdDocHasPageLabels(doc)
false
```
"""
function pdDocHasPageLabels(doc::PDDoc)
    catalog = pdDocGetCatalog(doc)
    return get(catalog, cn"PageLabels") !== CosNull
end

"""
```
    pdDocGetPageLabel(doc::PDDoc, pageno::Int) -> String
```
Returns the page label if the page has a page label associated to it.

As per PDF Specification 1.7 Section 12.4.2, a document may optionally define
page labels (PDF 1.3) to identify each page visually on the screen or in print.
Page labels and page indices need not coincide: the indices shallbe fixed,
running consecutively through the document starting from 0 for the first page,
but the labels may be specified in any way that is appropriate for the
particular document.

# Example
```
julia> pdDocGetPageLabel(doc, 3)
"ii"
```
"""
pdDocGetPageLabel(doc::PDDoc, pageno::Int) =
    cosDocGetPageLabel(doc.cosDoc, doc.catalog, pageno)

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

# Example

```
julia> pdDocGetInfo(doc)
Dict{String,Union{CDDate, String, CosObject}} with 7 entries:
  "Subject"  => "AU-B Australian Documents"
  "Producer" => "HPA image bureau 1998-1999"
  "Author"   => "IP Australia"
  "ModDate"  => D:19990527113911Z
  "Keywords" => "Patents"
  "Creator"  => "HPA image bureau 1998-1999"
  "Title"    => "199479714D"
```
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

# Example

```
julia> pdDocGetNamesDict(doc)

220 0 obj
<<
	/IDS	123 0 R
	/Dests	119 0 R
	/URLS	124 0 R
>>
endobj
```
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

# Example

```
julia> outline = pdDocGetOutline(doc)
555 0 R

julia> iob = IOBuffer();

julia> using AbstractTrees; print_tree(iob, outline)

julia> write(stdout, iob.data)
Contents
├─ Table of Contents
├─ 1. Introduction
├─ 2. Quick Steps - Kernel Compile
│  ├─ 2.1. Precautionary Preparations
│  ├─ 2.2. Minor Upgrading of Kernel
│  ├─ 2.3. For the Impatient
│  ├─ 2.4. Building New Kernel - Explanation of Steps
│  ├─ 2.5. Troubleshooting
...
```
"""
function pdDocGetOutline(doc::PDDoc)
    catalog = pdDocGetCatalog(doc)
    cosDoc = pdDocGetCosDoc(doc)
    tocobj = cosDocGetObject(cosDoc, catalog, cn"Outlines")
    tocobj === nothing && return nothing
    return PDOutline(doc, tocobj)
end

"""
```
    pdDocHasSignature(doc::PDDoc) -> Bool
```
Returns `true` when the document has at least one signature field.

This does not mean there is an actual digital signature embedded in the document.
A PDF document can be signed and content can be approved by one or more
reviewers. Signature fields are placeholders for storing and rendering such
information.

# Example
```
julia> pdDocHasSignature(doc)
true
```
"""
function pdDocHasSignature(doc::PDDoc)
    catalog = pdDocGetCatalog(doc)
    cosDoc = pdDocGetCosDoc(doc)
    acroform = cosDocGetObject(cosDoc, catalog, cn"AcroForm")
    acroform === CosNull && return false
    sigfobj  = cosDocGetObject(cosDoc, acroform, cn"SigFlags")
    sigfobj  === CosNull && return false
    return get(sigfobj) & 0x1 != 0
end

"""
```
    pdDocValidateSignatures(doc::PDDoc; export_certs=false) -> Vector{Dict{Symbol, Any}}
```
## Input
| param      | Description                                                  |
|:-----------|:-------------------------------------------------------------|
|doc         |The document for which all the signatures are to be validated.|
|export_certs|Optional keyword parameter when set, exports all the          |
|            |certificates that are embeded in the PDF document. These      |
|            |certificates can be for end-entities or one or more certifying|
|            |authorities.                                                  |
|            |Certificates are exported to the file `<PDF filename>.pem`.   |

## Output
Vector of dictionary objects representing one dictionary object for each
signature. The dictionary objects map the symbols to output as per the following
table. 

|Symbol    |Description                                                  |
|:---------|:------------------------------------------------------------|
|:Name     |The name of the person or authority signing the document.    |
|:P        |Object reference of the page in which the signature is found.|     
|:M        |The `CDDate` when the document was signed.                   |     
|:certs    |The certificates associated with every signature object.     |     
|:subfilter|The subfilter of PDF signature object.                       |
|:FQT      |Fully qualified title of the signature form.                 |
|:chain    |The certificate chain that validated the signature.          |
|:passed   |Validation status of the signature (true / false)            |
|:error_message| Error message returned during the validation            |
|:stacktrace| The stack dump of where the validation failure occurred    |

## Notes
1. Any additional certificates needed for validating a certificate trust chain
   has to be added manually to the *Trust Store* file at:
   `<Package Directory>/data/certs/cacerts.pem` in the PEM format. Normally,
   certificate authorities (root as well as intermediate) are represented in the
   trust store.
2. Presence of an end-entity certificate in the *Trust Store* ensures that the
   chain validation for the certificate does not have to be carried out. However,
   this is not considered a good practice for certificates as the certificate
   validation is an important attribute to avoid security breaches in the chain.
   In case of self-signed certificates with not CA capabilities this may be the
   only option. 
3. Validation of digital signatures are limited to the approval signature
   validation as per section 12.8.1 of PDF Spec. 1.7. Signatures for permissions
   and usage rights are not validated as per this method. This API only provides
   a validation report. It does not modify access to any parts of the document
   based on the validation output. The consumer of the API needs to take
   appropriate action based on the validation report as desired in their
   applications.
4. *Revocation* - When time is embedded in the signature as signing-time
   attribute or a signed timestamp or PDF sigature dictionary has M attribute,
   then those are picked up for validation. However, revocation information are
   not used during validation.
5. *PDF 2.0 Support* - The support is only experimental. While some subfilters
   like `/ETSI.CAdES.detached` are supported. Document Security Store (DSS) and
   Document Time Stamp (DTS) has not been implemented.

# Example
```
julia> r = pdDocValidateSignatures(doc);

julia> r[1] # Failure case
Dict{Symbol,Any} with 8 entries:
  :Name          => "JAYANT KUMAR ARORA"
  :P             => 1 0 R
  :M             => D:20190425173659+05'30
  :error_message => "Error in Crypto Library:
                        140322274480320:error:02001002:system library:..."
  :subfilter     => /adbe.pkcs7.sha1
  :stacktrace    => ["error(::String) at error.jl:33",
                     "openssl_error(::Int32) at PDCrypt.jl:96",
                     "PDFIO.PD.PDCertStore() at PDCrypt.jl:148",
                     ...]
  :FQT           => "Signature1"
  :passed        => false

julia> r[1] # Passed case
Dict{Symbol,Any} with 8 entries:
  :Name      => "JAYANT KUMAR ARORA"
  :P         => 1 0 R
  :M         => D:20190425173659+05'30
  :certs     => Dict{Symbol,Any}[Certificate Parameters...]
  :subfilter => /adbe.pkcs7.sha1
  :FQT       => "Signature1"
  :chain     => Dict{Symbol,Any}[Certificate Parameters...]
  :passed    => true

```
"""
function pdDocValidateSignatures(doc::PDDoc; export_certs=false)
    catalog = pdDocGetCatalog(doc)
    cosDoc = pdDocGetCosDoc(doc)
    acroform = cosDocGetObject(cosDoc, catalog, cn"AcroForm")
    acroform === CosNull && return 
    sigfobj  = cosDocGetObject(cosDoc, acroform, cn"SigFlags")
    (sigfobj  === CosNull || get(sigfobj) & 0x1 == 0) && return
    fields = cosDocGetObject(cosDoc, acroform, cn"Fields")
    fields === CosNull && return
    # The Dict{Symbol, Any} carries needed inherited properties
    # Currently only Page Number(P) and Fully Qualified Title
    # (FQT - non-spec) are used.
    sigflds = Vector{Tuple{IDD{CosDict}, Dict{Symbol, Any}}}()
    inherit = Dict{Symbol, Any}() 
    pd_get_signature_fields!(doc, fields, inherit, sigflds)
    ret = Vector{Dict{Symbol, Any}}()
    certmap = Dict{NTuple{2, String}, String}()
    for sig in sigflds
        pd_validate_signature(doc, sig)
        d = sig[2]
        push!(ret, d)
        cis = d[:certs]
        for ci in cis
            key = (ci[:subject], ci[:issuer])
            get!(certmap, key, ci[:text])
        end
    end
    export_certs || return ret
    if !isempty(certmap)
        bn = basename(doc.cosDoc.filepath)
        fname = splitext(bn)[1]*".pem"
        open(fname, "w") do io
            for val in values(certmap)
                print(io, val)
            end
        end
    end
    return ret
end
