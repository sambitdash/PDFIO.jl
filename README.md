# PDFIO

[![*nix Status](https://travis-ci.org/sambitdash/PDFIO.jl.svg?branch=master)](https://travis-ci.org/sambitdash/PDFIO.jl)
[![Win status](https://ci.appveyor.com/api/projects/status/9cocsctqdkx603q0?svg=true)](https://ci.appveyor.com/project/sambitdash/pdfio-jl)
[![codecov.io](http://codecov.io/github/sambitdash/PDFIO.jl/coverage.svg?branch=master)](http://codecov.io/github/sambitdash/PDFIO.jl?branch=master)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://sambitdash.github.io/PDFIO.jl/dev)
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://sambitdash.github.io/PDFIO.jl/stable)

PDFIO is a simple PDF API focused on processing text from PDF files. The
APIs is kept fairly simple and follows the PDF-32000-1:2008 specification as
downloaded from
[Adobe website](http://www.adobe.com/devnet/pdf/pdf_reference.html). The updated
ISO versions can be downloaded from ISO websites. The API does not consider
those versions yet. The API is developed in Julia keeping in mind the need for
the file format parsing in native form. More over the object structure of PDF
makes the API extend-able.

Technically,the PDFIO does not fully fit into the stream based file access APIs
like [JuliaIO/FileIO](https://github.com/JuliaIO/FileIO.jl). However, there is a general interest
to submit this API in that direction to ensure it's considered as a native file
format understood by Julia.

## About PDF

For people new to PDF development, PDF is a highly cross referenced file format
without any specific linear location to read content. You can consider this as a
form of a tree which needs to be read or understood as reading a tree. Hence, if
your application demands you need not have to scan the full file format to get
your job done. This is very different thinking than most file formats that are
parsed from beginning to end.

The second part to remember is PDF is a derivative of a Page Description
Language (PDL) like PostScript. The visual sanctity is considered most important
than document structure. Although, the document structure was introduced in PDF
as an afterthought a lot later, it's not core to the format. Unfortunately, the
creators never focus too much on this as it's a post processing over a print
stream.

## Structure of API

The API is segregated into 3 modules:

1. Common
2. Cos
3. PD

**Common** module has general system access and file access and parsing APIs.

**Cos** module is the low level file format for PDF. Carousel Object Structure
was original term proposed inside Adobe which later transformed into Acrobat.
Cos layer has the object structure, definition and the cross references to
access them.

**PD** module is the higher level document access layer. Accessing PDF pages or
extracting the content from there or understanding document rendering using
fonts or image objects will be typically in this layer. Please note that many
objects in the PD layer actually refer to the Cos structure. You can consider
PD Layer as the business logic while Cos Layer as the database for it.

## Intent and Limitations

The APIs are developed for text extraction as a major focus. The rendering and
printing aspects of PDF are not provided enough thoughts. Secondly, a native
script based language was chosen as PDF specification is highly misunderstood
and interpretations significantly vary from document creator to creator. A
script based language provides flexibility to fix issues as we discover more
nuances in the new files we discover. Thirdly, every well-developed native
library out in the market need connectors and PDF being a standard should have
native support in a modern language. Although, one can claim PDF is not the most
 ideal language for text processing, it's just ubiquitous and cannot be ignored.

 *Nothing stops anyone to extend this APIs into a fully developed PDF Library
 that's available to both commercial as well as non-commercial licensing under a
 flexible license model. I am happy to collaborate with anyone who sees value in
  extending this library in that direction. MIT License looks most flexible to
 the author for the time-being.*

### Common

1. Error handling is currently fairly weak with only errors or asserts leading
to termination. Ideally, if the PDF is structurally weak, there is no point
extracting content from the same. However, not all objects may be well-formed
a linient approach may be taken in the PD layers.


### Cos
1. Streams have larger number of filter types. Only Flate has been tested to
work reasonably.
2. Filterparms are varied and only PNG filter UP has been tested to some extent
as part of ObjectStream. RLE, ACII85, ASCIIHex are tested as well. Multiple
filters per stream has been tested as well.
3. Object stream extends attribute has not been considered. May not be needed
for a reader context.
4. Free indirect objects are ignored in the PDF file as it's not typically a
reader requirement.
5. No security is implemented for encrypted PDFs

### PD

1. PD layer is just barely developed for reading pages and extracting contents
from it.

## Reference to Adobe

It's almost impossible to talk PDF without reference to Adobe. All copyrights or
trademarks are that are owned by Adobe or ISO, which have been referred to
inadvertently without stating ownership, are owned by them. The author also
has been part of Adobe's development culture in early part of his career with
specific to PDF technology for about 2 years. However, the author has not been
part of any activities related to PDF development from 2003. Hence, this API can
 be considered a clean room development. Usage of words like
 Carousel and Cos are pretty much public knowledge and large number of reference
 to the same can be obtained from industry related websites etc.
 
 The package contains [Adobe Font Metrics (AFM)](http://www.adobe.com/devnet/font.html) for 14 Core Adobe fonts. 

## Test files

Not all PDF files that were used to test the library has been owned by the
author. Hence, the author cannot make those files available to general public
for distribution under the source code license. However, the author is grateful
to the PDF document [library](http://www.stillhq.com/pdfdb/db.html) maintained
by [mikal@stillhq.com](mikal@stillhq.com). However, these files are no longer
available in the link above. 

Some files are also included from
[openpreserve](https://github.com/openpreserve/format-corpus/tree/master/pdfCabinetOfHorrors).
These files can be distributed with
[CC0](https://creativecommons.org/publicdomain/zero/1.0/).

However, test files may have different licensing that the `PDFIO`. Hence we have
now uploaded most test files to another project under [PDFTest](https://github.com/sambitdash/PDFTest).

## Contribution

Contributions in form of PRs are welcome for any features you will like to develop for the PDFIO library. 
Contributors are requested to review the Issues section to understand the known issues and if they can take
up few tasks to complete, it will be definitely appreciated. 
