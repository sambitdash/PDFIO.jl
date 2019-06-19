# PDFIO

[![*nix Status](https://travis-ci.org/sambitdash/PDFIO.jl.svg?branch=master)](https://travis-ci.org/sambitdash/PDFIO.jl)
[![Win status](https://ci.appveyor.com/api/projects/status/9cocsctqdkx603q0?svg=true)](https://ci.appveyor.com/project/sambitdash/pdfio-jl)
[![codecov.io](http://codecov.io/github/sambitdash/PDFIO.jl/coverage.svg?branch=master)](http://codecov.io/github/sambitdash/PDFIO.jl?branch=master)
[![Doc Latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://sambitdash.github.io/PDFIO.jl/dev)
[![Doc Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://sambitdash.github.io/PDFIO.jl/stable)

PDFIO is a native Julia implementation for reading PDF files. It's an 100% Julia implementation of the PDF specification. Other than a few well established algorithms like flate decode (`zlib` library) or cryptographic operations (`openssl` library) almost all of the APIs are written in native Julia. 

## Need for a PDF Reader API 

The following are some of the benefits of utilizing this approach:

1. PDF files are in existence for over three decades. Implementations of the PDF writers are not always to the specification or they may even vary
   significantly from vendor to vendor. Everytime, you get a new PDF
   file there is a possibility that it may not work to the best interpretation
   of the specification. A script based language makes it easier for the
   consumer to quickly modify the code and enhance to their specific needs. 
   
2. When a higher level scripting language implements a C/C++ PDF library API the scope is confined to achieving certain high level application tasks like, graphics or text extraction; annotation or signature content extraction or page merging or extraction. However, this API represents the PDF specification as a model (in MVC parlance). Every object in PDF specification can be represented in some form through these APIs. Hence, objects can be utilized effectively to understand document structure or correlate documents in more meaningful ways. 
   
3. Potential to be extended as a PDF generator. Since, the API is written as an object model of PDF documents, it's easier to extend with additional PDF write or update capabilities.
   

There are also certain downsides to our utilizing the approach. Some are:

1. Any API that represents an object model of a document, tends to carry the complexity of introducing abstract objects, often opaque objects (handles) that are merely representational for an API user. They may not have any functional meaning. They also tend to be granular than a method that can complete a user level task.
   
2. The user may need to refer to the PDF specification for having a complete semantic understanding.
   
3. The amount of code needed to carry out certain tasks can be substantially higher. 
   
### Illustration

A popular package `Taro.jl` that utilizes Java based  [Apache Tika](http://tika.apache.org/), [Apache POI](http://poi.apache.org/) and [Apache FOP](https://xmlgraphics.apache.org/fop/) libraries for reading PDF and other file types may need the following code to extract text and other metadata from the document.

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

## Installation

The package can be added the project by the command below:

```julia
julia> Pkg.add("PDFIO")
```

The current version of the API requires `julia 1.0`. The detailed list of packages  `PDFIO` depends on can be seen in the [Project.toml](Project.toml) file. 

## Sample Code

The above mentioned code takes a PDF file `src` as input and writes the text data into a file named `out`. It enumerates all the pages in the document and extracts the text from the pages. The extracted text is written to the output file. 

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
    doc = pdDocOpen(src)
```
Provides `doc` handle that can be used for subsequence operations on the document.
```julia
    docinfo = pdDocGetInfo(doc) 
```
Metadata extracted from the PDF document. This value is retained and returned as the return from the function. 
```julia
    open(out, "w") do io
		npage = pdDocGetPageCount(doc)
```
Returns number of pages in the document
```julia
        for i=1:npage
            page = pdDocGetPage(doc, i)
```
Returns a `page` handle to the specific page given the number number index. 
```julia
            pdPageExtractText(io, page)
```
Extract text from the page and write it to the output file.
```julia
        end
    end
    pdDocClose(doc)
```
Close the document handle. The `doc` handle should not be used after this call
```julia
    return docinfo
end
```

As can be seen above, granular APIs are provided in `PDFIO` that can be used in combination to achieve a desirable task. For details, please refer to the [Architectural Overview](Architectural Overview).

## Contribution

Contributions in form of PRs are welcome for any feature you will like to develop for the `PDFIO` library. You are requested to review the [GitHub Issues](https://github.com/sambitdash/PDFIO.jl/issues) section to understand the known issues. You can take up few of the issues, work on them and submit a PR. If you come across a bug or are unable to use the APIs in any manner, feel free to submit an issue. 

## Similar Packages

[Taro.jl](https://github.com/aviks/Taro.jl) is an alternate package in Julia that provides reading and extracting content from a PDF files. 
