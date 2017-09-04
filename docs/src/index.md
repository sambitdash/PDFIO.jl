# API Structure and Design

The API is segregated into 3 modules:

1. Common
2. Cos
3. PD

**Common** module has general system access and file access and parsing APIs.
The *ParserState* type has been taken from the
[JuliaIO/JSON.jl](/JuliaIO/JSON.jl). The file headers are not added. Hence,
author acknowledges the efforts of the developers for the same package and
expects the same be honored by any person developing any derivative work.
*Note*-*ParserState* is no longer in use. The parser has been moved to the
*BufferedStreams* interfaces. Some minor helper methods are ported to the new
interface.

**Cos** module is the low level file format for PDF. Carousel Object Structure
was original term proposed inside Adobe which later transformed into Acrobat.
Cos layer has the object structure, definition and the cross references to
access them.

**PD** module is the higher level document access layer. Accessing PDF pages or
extracting the content from there or understanding document rendering using
fonts or image objects will be typically in this layer. Please note that many
objects in the PD layer actually refer to the Cos structure. You can consider
PD Layer as the business logic while Cos Layer as the database for it.

# Common
```@docs
CDTextString
CDDate
CDDate(::CDTextString)
CDRect
```
# COS Objects
```@docs
CosObject
    CosNull
CosString
CosName
@cn_str
CosNumeric
  CosInt
  CosFloat
CosBoolean
CosDict
CosArray
CosStream
CosIndirectObjectRef
```

# PD
```@docs
PDDoc
pdDocOpen
pdDocClose
pdDocGetCatalog
pdDocGetNamesDict
pdDocGetInfo
pdDocGetCosDoc
pdDocGetPage
pdDocGetPageCount
pdDocGetPageRange
pdPageGetContents
pdPageIsEmpty
pdPageGetCosObject
pdPageGetContentObjects
pdPageExtractText
```
## PDF Page objects
```@docs
PDPageObject
PDPageElement
PDPageObjectGroup
PDPageTextObject
PDPageTextRun
PDPageMarkedContent
PDPageInlineImage
PDPage_BeginGroup
PDPage_EndGroup
```

# Cos
```@docs
CosDoc
cosDocOpen
cosDocClose
cosDocGetRoot
cosDocGetObject
cosDocGetPageNumbers
```
