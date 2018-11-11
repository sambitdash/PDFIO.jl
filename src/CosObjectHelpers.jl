using ..Common
using Rectangle

import ..Common: CDDate
import Base: convert, promote_rule, Vector, String
import Rectangle: Rect

function convert(::Type{CDTextString}, xstr::CosXString)
    feff = [LATIN_F, LATIN_E, LATIN_F, LATIN_F]
    FEFF = [LATIN_UPPER_F, LATIN_UPPER_E, LATIN_UPPER_F, LATIN_UPPER_F]
    prefix = xstr.val[1:4]
    hasPrefix = (prefix == feff || prefix == FEFF)
    isUTF16   = hasPrefix || prefix[1:2] == UInt8[0x30, 0x30]
    data = xstr.val
    buffer = data |> String |> hex2bytes
    if isUTF16
        len2 = div(length(buffer), 2)
        utf_16_arr = zeros(UInt16, hasPrefix ? len2-1 : len2)
        utf_16_data = reinterpret(UInt8, utf_16_arr)
        if (0x04030201 == ENDIAN_BOM)
            for i=1:len2
                (buffer[2i-1], buffer[2i]) = (buffer[2i], buffer[2i-1])
            end
        end
        hasPrefix ? copyto!(utf_16_data, 1, buffer, 3, 2len2-2) :
            copyto!(utf_16_data, 1, buffer, 1, 2len2)
        str = transcode(CDTextString, utf_16_arr)
    else
        str = CDTextString(PDFEncodingToUnicode(buffer))
    end
    return str
end

String(xstr::CosXString) = convert(String, xstr)

convert(::Type{Vector{UInt8}}, xstr::CosXString) =
    xstr |> get |> String |> hex2bytes

convert(::Type{Vector{UInt8}}, str::CosLiteralString) = str |> get

Vector{T}(str::CosString) where {T <: UInt8} = convert(Vector{UInt8}, str)

convert(::Type{CDTextString}, lstr::CosLiteralString) =
    CDTextString(PDFEncodingToUnicode(lstr.val))

String(lstr::CosLiteralString) = convert(String, lstr)

convert(::Type{T}, i::CosInt) where {T <: Number} = convert(T, get(i))

convert(::Type{T}, f::CosFloat) where {T <: Number} = convert(T, get(f))

convert(::Type{CosFloat}, i::CosInt) = i.val |> Float32 |> CosFloat

promote_rule(::Type{CosFloat}, ::Type{CosInt}) = CosFloat

convert(::Type{CDRect}, a::CosArray) = CDRect(get.(a.val)...)

Rect(a::CosArray) = convert(Rect, a)

convert(::Type{CDDate}, ls::T) where {T <: CosString} = CDDate(CDTextString(ls))

CDDate(str::CosString) = convert(CDDate, str)

convert(::Type{CDTextString}, name::CosName) =
    CDTextString(split(String(name.val), '_'; limit=2)[2])

String(name::CosName) = convert(String, name)
