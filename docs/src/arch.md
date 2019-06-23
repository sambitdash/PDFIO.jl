# Architecture and Design

The design philosophy of PDF documents can be understood by the article written
by John Warnock, founding CEO of Adobe Systems, called the
[Camelot](http://www.planetpdf.com/planetpdf/pdfs/warnock_camelot.pdf)
paper. Unlike, PostScript which is a Turing complete programming language, PDF
is a file format. The operators in PDF do not leave a side effect on an
execution stack, that can be further exploited by the subsequent
operators. While one need not have full understanding of PostScript to
understand PDF general complexities of a *page description language (PDL)* 
like PostScript are seen in PDFs as well. Here are a few simple scenarios of
similarities and dissimilarities of PDF vs PostScript are presented here. This
will help you understand the design principles of PDF.

1. **Execution Order and Page**: PostScript is an execution engine. It would
   execute the code as the operators are received and results are left on the
   execution stack as side-effects. Depending on the device rendering
   capabilities, PostScript would load the rendered output to the device on a
   call of `showpage`. PDF does not have the flexibility of execution of a
   programming language. Generally, PDF content are organized as page
   objects. The content to be rendered and the resources (fonts and images) are
   associated with a page. Moreover, the content is rendered in the order in
   which they appear. Unless otherwise specified, the ink is considered
   opaque. Thus a content rendered later may overwrite the content rendered
   earlier if there is an overlap.
2. **Content Order vs. Reading Order**: PDLs focus on final look and feel of the
   output and not the reading order of the text or artifacts. For example, fonts
   tend to be an expensive resource to load at least under low memory
   conditions. Once loaded an execution engine may like to render all the
   content utilizing the font resource earlier than render the artifacts in the
   reading order. A document optimized for such purpose will tend to organize
   all text utilizing a specific fonts at one place.
3. **Content Objects vs. Non-Content Objects**: Without getting much into the
   definition complexities, we can state a content leaves an artifact on a page
   and is rendered. While some other objects may affect the user interface or
   provide additional document metadata information and they are not rendered on
   a PDF page. One example will be PDF outlines or navigation links. They only
   are shown on a user interface and not on a rendered page.
4. **Random vs. Sequential Access**: PDF files are designed for random access of
   the document. You can get to any page and access the contents of the
   page. While PostScript was not designed for that purpose. It typically will
   be loaded once and executed.

## PDF specification ISO-32000-1 and ISO-32000-2

The API is developed around PDF specification, notably around ISO-32000-1, that
can be downloaded from
[Adobe](https://www.adobe.com/content/dam/acom/en/devnet/pdf/pdfs/PDF32000_2008.pdf). Some
attempts have been made to consider certain features of PDF-2.0
([ISO-32000-2](https://www.iso.org/standard/63534.html)). However, the attempts
have been made with draft versions of the specification. The final version of
the specification has not been reviewed for the implementations. Hence, the
support is only experimental.

The API derives heavily from the PDF specification and tries to be as compliant
to the specification as practical. Any significant discrepancies in the APIs
have to be compared with the PDF specification for clarification and
accuracy. The API is an extension to the PDF specification. Hence, it's
recommended the users of the API refer to the specification as well for a
clearer understanding of the working of the API. Where a feature is best
understood from the specification, reference to the specification will be
provided than elaborating it in the API documentation.

## PDF Components

PDF specification identifies the following components of a file. For details
about the components please refer to the Chapter-7 of the PDF specification 1.7.

1. Objects
2. File Structure
3. Document Structure
4. Content Objects

Based on the components being used the API is divided into two layers.

### COS Layer

#### Objects

Carousel Object System (COS) is an object representation for both simple and
composite objects. [`CosObject`](@ref) is the highest level abstraction that all
the objects inherit from. The objects supported in PDF are:

##### Simple 

- [`CosNull`](@ref) - A singleton object representing a `null` in PDF. 
- [`CosBoolean`](@ref) Values: `CosTrue` or `CosFalse`
- [`CosNumeric`](@ref)(abstract) Concrete Types: [`CosInt`](@ref),
  [`CosFloat`](@ref)
- [`CosString`](@ref)(abstract) - String in PDF is a collection of binary data
  and does not represent a meaningful text unless it's associated with a
  specific font and encoding. For clarity, please refer to the section 7.3.4 and
  7.9.3 of the PDF specification. `Strings` can be represented as hexadecimal
  notations or direct byte values. They are internally knows as `CosXString` or
  `CosLiteralString` respectively. The consumers of the APIs do not have to be
  affected by such distinctions.
- [`CosName`](@ref) - Very similar to `Symbol` objects of Julia. 

##### Composite

- [`CosArray`](@ref) - an array collection of `CosObjects`. 
- [`CosDict`](@ref) - an associative collection of name value pairs where names
  are of type `CosName` and values can be of any `CosObject`
- [`CosStream`](@ref) - very similar to `CosDict`, but the dictionary is
  followed by arbitrary binary data. This data can be in a compressed and
  encoded form by a series of algorithms known as filters.

#### File Structure

PDF file structure provides how the objects are arranged in a PDF file. PDF is
designed to be accessed in a random access order. Some of the objects in PDF
like fonts can be referred from multiple page objects. To address these concerns
objects are provided reference identifiers and mappings are provided from
various locations in the PDF files. Moreover, to reduce the size of the files,
the objects are put inside stream containers and can be compressed. Access to a
specific object reference may need several lookups before the actual object can
be traced. All these lead to a fairly complex arrangement of
objects. [`CosDoc`](@ref) wraps all the object reference schemes and provide a
simplified API called [`cosDocGetObject`](@ref) and simplifies object look up.
Thus any PDF object can be classified into the following forms based on how they
are represented in a document:

- *Direct Objects* - Direct objects are defined where they are referred or used.
- *Indirect Objects* - Indirect objects have reference identifiers, there
  location in a PDF document is described through a Object Reference identifier.

```PDF
146 0 obj # Object Refence (146, 0) can be indirect object
<<
  	/Subject	(AU-B Australian Documents) # CosString is a direct object
  	/CreationDate	(27 May 1999 11: 1) 
  	/Title	(199479714D)
  	/ModDate	(D:19990527113911)
  	/Author	(IP Australia)
  	/Keywords	(Patents)
  	/Creator	(HPA image bureau 1998-1999)
  	/Producer	(HPA image bureau 1998-1999)
>>
endobj
```

Normally, direct and indirect objects can be used interchangeably. But, there
are certain cases where the specification dictates objects will be either direct
or indirect. For example, objects used inside of a page content can be only
direct objects. In such cases, names are used instead of object
identifiers. Resources like fonts in a page content are names and not object
identifiers.

#### Document Structure

There are additional structures in the document that are commonly used inside a
PDF document. Some of them are:

- *Document Catalog Dictionary* - The root object from where PDF document
  reading begins. For example, this has the reference to a page tree.

  ```PDF
  154 0 obj
  <<
  	/Type	/Catalog
  	/Pages	152 0 R
  >>
  endobj
  ```
- *Page Tree* - Pages in a document can be arranged in a generic tree
  structure. While for better access binary search trees are the recommended
  approach there is no hard rule and document creators are free to define the
  structure in any manner that's relevant to them.
  ```PDF
  152 0 obj
  <<
  	/Type	/Pages
  	/Kids	[147 0 R 148 0 R 149 0 R 150 0 R 151 0 R ]
  	/Count	30
  >>
  endobj
  ```
In the above example, `Kids`  represents a direct `CosArray` that contains 
reference object identifiers `(147 0), (148 0),  (149 0),  (150 0),  (151 0)`.

- *Name Dictionary* - Associates various named components to other hierarchical
  structures in a document. Typically, represented as an object referenced in
  the document catalog.

#### Is COS Layer Sufficient for PDF parsing?

Since COS layer represents the objects, document structure and file structure,
is it sufficient to parse a PDF file? The answer to this question is mostly
yes. You can virtually do anything with a PDF file using only methods defined in
the COS layer.

- But, this will enforce one to follow the PDF specification in totality for
  extracting any information from a PDF file. But, that can overwhelm one to
  implement any significant task with PDF files.
- Secondly, COS layer does not expose the `Contents` objects of the PDF
  pages. Hence, no rendering related activity can be carried out in this layer.

A PD Layer is developed to create functional PDF tasks as well as to render PDF
content objects. However, when a functional implementation is not available in a
PD Layer, COS Layer can be used to implement a functionality with low level
APIs. Most of the PD Layer implementations utilize methods from the COS
Layer. However, a good COS layer method implementation should never refer the a
methods of the PD layer.

#### Example

Extracting files embedded inside a PDF document is not currently available as a
PD Layer functionality. However, the same has been achieved using COS layer
functions. The code is available in the automated test cases as well.

```julia
function pdfhlp_extract_doc_attachment_files (filename, dir=tempdir())
  	file=rsplit(filename, '/',limit=2)
  	filenm=file[end]
  	dirpath=joinpath(dir,filenm)
  	isdir(dirpath) && rm(dirpath;force=true, recursive=true)
  	mkdir(dirpath)	
  	doc=pdDocOpen(filename)
  	cosDoc=pdDocGetCosDoc(doc)
  	try
    	npage= pdDocGetPageCount(doc)
    	for i=1:npage
      		page = pdDocGetPage(doc, i)
      		cospage = pdPageGetCosObject(page)
      		annots = cosDocGetObject(cosDoc, cospage, cn"Annots")
      		annots === CosNull && continue
      	end
      	annotsarr=get(annots)
      	for annot in annotsarr
        	annotdict = cosDocGetObject(cosDoc, annot)
        	subtype = get(annotdict, cn"Subtype")
        	if (subtype == cn"FileAttachment")
          		filespec = cosDocGetObject(cosDoc, annotdict, cn"FS")
          		ef = get(filespec, cn"EF")
          		filename = get(filespec, cn"F") 
                #UF could be there as well.
          		stmref = get(ef, cn"F")
          		stm = cosDocGetObject(cosDoc, stmref)
          		bufstm = get(stm)
          		buf = read(bufstm)
          		close(bufstm)
          		path = joinpath(dirpath, get(filename))
          		write(path, buf)
        	end
      	end
  	finally
 		pdDocClose(doc)
  	end
end
```

As can be seen, this requires one to understand the PDF specification to skim
through the PDF objects to extract the file from the relevant object where it's
embedded.

#### Limitations

While the implementation of the COS layer is fairly elaborate, PDF security
handlers are not implemented as part of this API. Hence, this implementation is
not effective where a document is encrypted with passwords. Such documents
typically have all the string and stream objects encrypted using document
passwords. Hence, cannot be read by `PDFIO`.

### PD Layer

Understanding the scope of COS layer leaves out the following functionalities
for the PD layer.

1. Extract and render the Contents in of a PDF page. This ensures the contents
   are organized in a hierarchical grouping, that can be used for rendering of
   the content. Rendering is used here in a generic context and not confined to
   painting on a raster device. For example, extracting document text can also
   be considered as a rendering task. `pdPageExtractText` is an apt example of
   the same.
2. Provide functional tasks to PDF document access. A few of such
   functionalities are:
   - Getting the page count in a document
   - Finding labels in a document page
   - Extracting outlines defined in the document
   - Extracting document metadata information
   - Validation of signatures in a PDF document
   - Extracting fonts and font attributes

PD layer is an ever expanding layer. As newer functionality are implemented PD
layer will introduce newer methods, that will enhance the library capabilities.

#### Limitations

Although PD layer has been developed, PDF specification is quite
vast. Functionalities currently exposed are mostly implemented to aid text
extraction from document better. However, more advanced features can be added as
and when needed to the APIs. Writing PDF output has not been implemented. When
implemented, PD layer needs to be expanded for the same.

### Common Data Structures (CD Layer)

PDF is a platform independent file format. This requires, certain features that
needs to be abstracted to support multitude of platforms. Here are some object
types where certain special handing of data may be needed:

- *Strings* - For example, text which are part of content objects can be
   represented very well using `CosString` objects. But, PDF may have text that
   do not associate a font or encoding thereof associated to string objects. In
   such cases, unicode strings or PDF encoded strings are represented. PDF
   encoding is a consistent representation of printable characters that can be
   applied irrespective of platform where the file is used. This can be
   considered as the default encoding of a PDF file.
- *Date and Time* - The PDF file may have creation time, modification time
  embedded in the document. Such data is represented as a string
  object. However, translating such time attributes to time objects for
  comparison is definitely essential.
- *File and File System* - Unix, Microsoft Windows, Mac OS X have their own file
  representations that may be different. Julia itself being a platform
  independent language caters directly to such needs.
- *Name tree and Number trees* - General purpose tree like data structures that
  hold a hierarchy based on name strings or numbers. Although, these objects are
  defined they are not exposed outside as they generally are used in the
  internal context of operations. An API user may not normally need to
  manipulate them.

Now that you have some understanding of the PDF architecture you can refer to
the [API Reference](@ref) to understand the scope of each method and use them as
needed for your applications. Please keep the PDF specification handy to
understand the nuances of the APIs.
