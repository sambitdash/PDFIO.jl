__precompile__()

module PDFIO

include("Common.jl") #Module Common
include("Cos.jl")    #Module Cos
include("PD.jl")     #Module PD

using .Common
export CDTextString, CDDate, CDRect, getUTCTime

using .PD
export  PDDoc,
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
            pdDocValidateSignatures,
        PDPage,
            pdPageGetContents,
            pdPageIsEmpty,
            pdPageGetCosObject,
            pdPageGetContentObjects,
            pdPageGetMediaBox,
            pdPageGetFonts,
            pdPageGetCropBox,
            pdPageExtractText,
            pdPageGetPageNumber,
        PDPageObject,
            PDPageObjectGroup,
                PDPage_BeginGroup, PDPage_EndGroup,
            PDPageTextObject,
            PDPageMarkedContent,
            PDPageElement,
            PDPageTextRun,
            PDPageInlineImage,
        PDFont,
            pdFontIsBold,
            pdFontIsItalic,
            pdFontIsFixedW,
            pdFontIsAllCap,
            pdFontIsSmallCap,
        PDOutline,
            PDDestination,
            PDOutlineItem,
                pdOutlineItemGetAttr

using .Cos
export  CosDoc,
            cosDocOpen,
            cosDocClose,
            cosDocGetRoot,
            cosDocGetObject,
            cosDocIsEncrypted,
        CosObject,
            CosNull, CosDict, CosString, CosArray, CosStream,
            CosIndirectObjectRef, set!,
        CosBoolean,
            CosTrue, CosFalse,
        CosNumeric,
            CosFloat, CosInt,
        CosName,
            @cn_str,
        CosTreeNode,
            createTreeNode

end # module
