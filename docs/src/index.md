# API Reference

The APIs are segregated into 3 modules:

1. Common
2. COS
3. PD

**Common** module has general system access and file access and parsing APIs.

**COS** module is the low level file format for PDF. Carousel Object Structure
was original term proposed inside Adobe which later transformed into Acrobat.
COS layer has the object structure, definition and the cross references to
access them.

**PD** module is the higher level document access layer. Accessing PDF pages or
extracting the content from there or understanding document rendering using
fonts or image objects will be typically in this layer. 

A detailed explanation of these layers and their rational has been explained in the [Architecture and Design](arch.md) section.

# Common
```@docs
CDTextString
CDDate
CDDate(::CDTextString)
getUTCTime
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
set!(::CosDict, ::CosName, ::CosObject)
CosArray
length(::CosArray)
CosStream
CosIndirectObjectRef
get
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
pdDocHasPageLabels
pdDocGetPageLabel
pdDocGetOutline
pdDocHasSignature
pdDocValidateSignatures
pdPageGetContents
pdPageIsEmpty
pdPageGetCosObject
pdPageGetContentObjects
pdPageGetMediaBox
pdPageGetFonts
pdPageExtractText
pdPageGetPageNumber
pdFontIsBold
pdFontIsItalic
pdFontIsFixedW
pdFontIsAllCap
pdFontIsSmallCap
PDOutline
PDOutlineItem
PDDestination
pdOutlineItemGetAttr
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

# COS Methods
```@docs
CosDoc
cosDocOpen
cosDocClose
cosDocGetRoot
cosDocGetObject
```
