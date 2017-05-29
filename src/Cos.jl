module Cos

#using ..Common:ispdfdigit,ispdfspace,PERCENT,MINUS_SIGN,DIGIT_ZERO,PERIOD,
#               TRAILER
#using ..Common.Parser


using ..Common
using ..Common.Parser

include("CosObject.jl")
include("CosReader.jl")
include("CosDoc.jl")

end
