__precompile__()

module PDFIO

using Compat

include("Common.jl") #Module Common
include("Cos.jl")    #Module Cos

include("PD.jl")     #Module PD

#export Common, Cos, PD

using .Common
export CDTextString, CDDate, CDRect

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
        PDPage,
            pdPageGetContents,
            pdPageIsEmpty,
            pdPageGetCosObject,
            pdPageGetContentObjects,
            pdPageExtractText

using .Cos
export  CosDoc,
            cosDocOpen,
            cosDocClose,
            cosDocGetRoot,
            cosDocGetObject,
            cosDocGetPageNumbers,
        CosObject,
            CosNull, CosDict, CosString, CosArray, CosStream, CosIndirectObjectRef,
        CosBoolean,
            CosTrue, CosFalse,
        CosNumeric,
            CosFloat, CosInt,
        CosName,
            @cn_str,
        CosTreeNode,
            createTreeNode

end # module
