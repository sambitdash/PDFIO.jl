# PDFIO

[![*nix Status](https://travis-ci.org/sambitdash/PDFIO.jl.svg?branch=master)](https://travis-ci.org/sambitdash/PDFIO.jl)
[![Win status](https://ci.appveyor.com/api/projects/status/9cocsctqdkx603q0?svg=true)](https://ci.appveyor.com/project/sambitdash/pdfio-jl)
[![codecov.io](http://codecov.io/github/sambitdash/PDFIO.jl/coverage.svg?branch=master)](http://codecov.io/github/sambitdash/PDFIO.jl?branch=master)
[![Doc Latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://sambitdash.github.io/PDFIO.jl/dev)
[![Doc Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://sambitdash.github.io/PDFIO.jl/stable)
[![JOSS status](http://joss.theoj.org/papers/742f48b0842cddf715b58a0bca2ffeb3/status.svg)](http://joss.theoj.org/papers/742f48b0842cddf715b58a0bca2ffeb3)

PDFIO is a native Julia implementation for reading PDF files. It's an 100% Julia 
implementation of the PDF specification. Other than a few well established 
algorithms like flate decode (`zlib` library) or cryptographic operations 
(`openssl` library) almost all of the APIs are written in native Julia. 

## Need for a PDF Reader API 

The following are some of the benefits of utilizing this approach:

1. PDF files are in existence for over three decades. Implementations of the PDF
   writers are not always to the specification or they may even vary
   significantly from vendor to vendor. Everytime, you get a new PDF
   file there is a possibility that it may not work to the best interpretation
   of the specification. A script based language makes it easier for the
   consumers to quickly modify the code and enhance to their specific needs. 
   
2. When a higher level scripting language implements a C/C++ PDF
   library API, the scope is kept limited to achieving certain high 
   level tasks like, graphics or text extraction; annotation or
   signature content extraction; or page extraction or merging. 
   
   However, `PDFIO` represents the PDF specification as a model in the 
   Model, View and Controller parlance. A PDF file can be represented 
   as a collection of interconnected Julia structures. Those 
   structures can be utilized in granular tasks or simply can be used 
   to understand the structure of the PDF document. 

   As per the PDF specification, text can be presented as part of the
   page content stream or inside PDF page annotations. An API like 
   `PDFIO` can create two categories of object types. One representing
   the text object inside the content stream and the other for the 
   text inside an annotation object. Thus, providing flexibility to 
   the API user. 
    
3. Since, the API is written as an object model of PDF documents, it's 
   easier to extend with additional PDF write or update capabilities. 
   Although, the current implementation does not provide the PDF 
   writing capabilities, the foundation has been laid for future 
   extension.

There are also certain downsides to this approach:

1. Any API that represents an object model of a document, tends to
   carry the complexity of introducing abstract objects. They can be
   opaque objects (handles) that are representational specific to the 
   API. They may not have any functional meaning. The methods are
   granular and may not complete one use level task. The amount of code
   needed to complete a user level task can be substantially higher. 
   
   In `PDFIO` the following steps have to be carried out: 
   a. Open the PDF document and obtain the document handle.  
   b. Query the document handle for all the pages in the document. 
   c. Iterate the pages and obtain the page object handles for each of
      the pages.  
   d. Extract the text from the page objects and write to a file IO.  
   e. Close the document ensuring all the document resources are 
      reclaimed.
2. The API user may need to refer to the PDF specification
   (PDF-32000-1:2008)[@Adobe:2008] for semantic understanding of PDF 
   files in accomplishing some of the tasks. For example, the workflow 
   of PDF text extraction above is a natural extension from how text is 
   represented in a PDF file as per the specification. A PDF file is 
   composed of pages and text is represented inside each page content 
   object. The object model of `PDFIO` is a Julia language 
   representation of the PDF specification. 


## Installation

The package can be added to a project by the command below:

```julia
julia> Pkg.add("PDFIO")
```

The current version of the API requires `julia 1.0`. The detailed list of packages  `PDFIO` depends on can be seen in the [Project.toml](Project.toml) file. 

## Sample Code

The below mentioned code takes a PDF file `src` as input and writes the text data into a file `out`. It enumerates all the pages in the document and extracts the text from the pages. The extracted text is written to the output file. 

```julia {.line_numbers}
"""
​```
    getPDFText(src, out) -> Dict 
​```
- src - Input PDF file from where text is to be extracted
- out - Output TXT file where the output will be written
return - A dictionary containing metadata of the document
"""
function getPDFText(src, out)
    # handle that can be used for subsequence operations on the document.
    doc = pdDocOpen(src)
    
    # Metadata extracted from the PDF document. 
    # This value is retained and returned as the return from the function. 
    docinfo = pdDocGetInfo(doc) 
    open(out, "w") do io
    
        # Returns number of pages in the document       
        npage = pdDocGetPageCount(doc)

        for i=1:npage
        
            # handle to the specific page given the number index. 
            page = pdDocGetPage(doc, i)
            
            # Extract text from the page and write it to the output file.
            pdPageExtractText(io, page)

        end
    end
    # Close the document handle. 
    # The doc handle should not be used after this call
    pdDocClose(doc)
    return docinfo
end
```

### Interactive Code Examples

One can also execute the following interactive commands on a Julia REPL to access objects of a PDF file. 

#### Getting Document Handle
```julia
julia> doc = pdDocOpen("test/sample-google-doc.pdf")

PDDoc ==>

CosDoc ==>
	filepath:		/home/sambit/.julia/dev/PDFIO/test/sample-google-doc.pdf
	size:			21236
	hasNativeXRefStm:	 true
	Trailer dictionaries: 

Catalog:
4 0 obj
<<
	/Pages	14 0 R
	/Type	/Catalog
>>
endobj

isTagged: none
```

#### Getting Document Info
```
julia> info = pdDocGetInfo(doc)
Dict{String,Union{CDDate, String, CosObject}} with 1 entry:
  "Producer" => "Skia/PDF m79"
```
#### Getting the Number of Pages
```
julia> npage = pdDocGetPageCount(doc)
1
```
#### Get the Page Handle
```
julia> page = pdDocGetPage(doc, 1)
PDFIO.PD.PDPageImpl(
...
)
```
#### View Page Text Contents
```
julia> pdPageExtractText(stdout, page);
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut 
        labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco 
        laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in 
        voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non 
        proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
```

As can be seen above, granular APIs are provided in `PDFIO` that can be used in combination to achieve a desirable task. For details, please refer to the [Architecture and Design](@ref).

## Features

`PDFIO` is implemented in layers enabling following features:

1. Extract and render the Contents in of a PDF page. This ensures the contents are organized in a hierarchical grouping, that can be used for rendering of the content. Rendering is used here in a generic sense and not confined to painting on a raster device. For example, extracting document text can also be considered as a rendering task. `pdPageExtractText` is an apt example of the same. 
2. Provide functional tasks to PDF document access. A few of such functionalities are:
   - Getting the page count in a document ([`pdDocGetPageCount`](@ref))
   - Finding labels in a document page ([`pdDocGetPageLabel`](@ref))
   - Extracting outlines defined in the document ([`pdDocGetOutline`](@ref))
   - Extracting document metadata information ([`pdDocGetInfo`](@ref))
   - Validation of signatures in a PDF document ([`pdDocValidateSignatures`](@ref))
   - Extracting fonts and font attributes ([`pdPageGetFonts`](@ref), [`pdFontIsItalic`](@ref) etc.)
3. Access low level PDF objects and obtain information when high level APIs do not exist. 

The [Architecture and Design](@ref) discusses some of these scenarios. 

## Licensing

`PDFIO` is developed to contribute to both commercial activities and scientific research alike. However, we strongly discourage usage of this product for any illegal, immoral or unethical purposes. [PDFIO License](@ref) while provides rights under a permissible `MIT Expat License`, is conditioned upon maintaining strong moral, ethical and legal standards of the final outcome.

*This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit. (http://www.openssl.org/)*

## Contribution

Contributions in form of PRs are welcome for any feature you will like to develop for the `PDFIO` library. You are requested to review the [GitHub Issues](https://github.com/sambitdash/PDFIO.jl/issues) section to understand the known issues. You can take up few of the issues, work on them and submit a PR. If you come across a bug or are unable to use the APIs in any manner, feel free to submit an issue. 

## Similar Packages

[Taro.jl](https://github.com/aviks/Taro.jl) is an alternate package in Julia that provides reading and extracting content from a PDF files. 

## Reference to Adobe

It's almost impossible to talk PDF without reference to Adobe. All copyrights or
trademarks that are owned by Adobe or ISO, which have been referred to
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

