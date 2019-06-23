---
title: 'PDFIO: PDF Reader Library for native Julia'
tags:
  - Julia
  - PDF
  - document archive
  - data extraction
  - text extraction
  - data mining
  - data management
authors:
  - name: Sambit Kumar Dash
    orcid: 0000-0003-4856-7244
    affiliation: "1"
affiliations:
 - name: Director, Lenatics Solutions Pvt. Ltd.
   index: 1
date: 26 April 2019
bibliography: paper.bib
---

# Summary

Portable Document Format (PDF) is the most ubiquitous file format for
text, scientific research, legal documentation and many other domains
for information dissemination and presentation. Being a final form
format of choice, a large body of text is currently archived in this
format. Julia is an upcoming programming language in the field of data
sciences with focus on text analysis. Extracting archived content to
text is highly beneficial to the language usage and adoption.

``PDFIO`` is an API developed purely in Julia. Almost, all the
functionalities of PDF understanding is entirely written from scratch
in Julia with only exception of certain (de)compression codecs and
cryptography, where standard open source libraries are being used.

The following are some of the benefits of utilizing this approach:

1. PDF files are in existence for over three decades. Implementations
   of the PDF writers are not always accurate to the specification or
   they may even vary significantly from vendor to vendor. Every time,
   someone gets a new PDF file there is a possibility that it may not
   work to the best interpretation of the specification. A script
   based language makes it easier for the consumers to quickly modify
   the code and enhance to their specific needs.
   
2. When a higher level scripting language implements a C/C++ PDF
   library API, the scope is confined to achieving certain high level
   application tasks like, graphics or text extraction; annotation or
   signature content extraction or page merging or
   extraction. However, this API represents the PDF specification as a
   model (in Model, View and Controller parlance). Every object in PDF
   specification can be represented in some form through these
   APIs. Hence, objects can be utilized effectively to understand
   document structure or correlate documents in more meaningful ways.
    
3. Potential to be extended as a PDF generator. Since, the API is
   written as an object model of PDF documents, it's easier to extend
   with additional PDF write or update capabilities.
   
There are also certain downsides to this approach:

1. Any API that represents an object model of a document, tends to
   carry the complexity of introducing abstract objects, often opaque
   objects (handles) that are merely representational for an API
   user. They may not have any functional meaning. The methods tend to
   be granular than a method that can complete a user level task.
2. The user may need to refer to the PDF specification
   (PDF-32000-1:2008)[@Adobe:2008] for having a complete semantic
   understanding.
3. The amount of code needed to carry out certain tasks can be
   substantially higher.
   
## Illustration

A popular package `Taro.jl`[@Avik:2013] that utilizes Java based [Apache
Tika](http://tika.apache.org/), [Apache POI](http://poi.apache.org/)
and [Apache FOP](https://xmlgraphics.apache.org/fop/) libraries for
reading PDF and other file types may need the following code to
extract text and other metadata from the document.

```julia
using Taro
Taro.init()
meta, txtdata = Taro.extract("sample.pdf");

```

While the same with `PDFIO` may look like below:

```julia
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
While `PDFIO` requires a larger number of lines of code, it definitely
provides a more granular set of APIs.

# Functionality

`PDFIO` is implemented in layers enabling following features:

1. Extract and render the Contents in of a PDF page. This ensures the
   contents are organized in a hierarchical grouping, that can be used
   for rendering of the content. Rendering is used here in a generic
   sense and not confined to painting on a raster device. For example,
   extracting document text can also be considered as a rendering
   task. `pdPageExtractText` is an apt example of the same.
2. Provide functional tasks to PDF document access. A few of such
   functionalities are:
   - Getting the page count in a document (`pdDocGetPageCount`)
   - Finding labels in a document page (`pdDocGetPageLabel`)
   - Extracting outlines defined in the document (`pdDocGetOutline`)
   - Extracting document metadata information (`pdDocGetInfo`)
   - Validation of signatures in a PDF document (`pdDocValidateSignatures`)
   - Extracting fonts and font attributes (`pdPageGetFonts`,
     `pdFontIsItalic` etc.)
3. Access low level PDF objects (`CosObject`) and obtain information
   when high level APIs do not exist. These kinds of functionalities
   are mostly related to the file structure of the PDF documents and
   also known as the `COS` layer APIs.


# Acknowledgements

We acknowledge contributions of all the community developers who have
contributed to this effort. Their contribution can be viewed at:
https://github.com/sambitdash/PDFIO.jl/graphs/contributors

# References
