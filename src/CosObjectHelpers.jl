using ..Common
import Base: convert

function convert(::Type{CDTextString}, xstr::CosXString)
    const feff = [LATIN_F, LATIN_E, LATIN_F, LATIN_F]
    const FEFF = [LATIN_UPPER_F, LATIN_UPPER_E, LATIN_UPPER_F, LATIN_UPPER_F]
    prefix = xstr.val[1:4]
    hasPrefix = (prefix == feff || prefix == FEFF)
    isUTF16   = hasPrefix || prefix[1:2] == UInt8[0x30, 0x30]
    data = xstr.val
    buffer = data |> String |> hex2bytes
    if isUTF16
        len2 = div(length(buffer),2)
        utf_16_arr = Vector{UInt16}(hasPrefix ? len2-1 : len2)
        utf_16_data = reinterpret(UInt8, utf_16_arr)
        if (0x04030201 == ENDIAN_BOM)
            for i=1:len2
                (buffer[2i-1], buffer[2i]) = (buffer[2i], buffer[2i-1])
            end
        end
        hasPrefix ? copy!(utf_16_data, 1, buffer, 3, 2len2-2) :
            copy!(utf_16_data, 1, buffer, 1, 2len2)
        str = transcode(CDTextString, utf_16_arr)
    else
        str = CDTextString(PDFEncodingToUnicode(buffer))
    end
    return str
end

convert(::Type{Vector{UInt8}}, xstr::CosXString) = xstr |> get |> String |> hex2bytes

convert(::Type{Vector{UInt8}}, str::CosLiteralString) = str |> get

convert(::Type{CDTextString}, lstr::CosLiteralString) =
    CDTextString(PDFEncodingToUnicode(lstr.val))

convert{T <: Number}(::Type{T}, i::CosInt) = T(get(i))

convert{T <: Number}(::Type{T}, f::CosFloat) = T(get(f))

convert(::Type{CDRect}, a::CosArray) = CDRect(a...)

convert{T <: CosString}(::Type{CDDate}, ls::T) = CDDate(CDTextString(ls))

convert(::Type{CDTextString}, name::CosName) =
    CDTextString(split(String(name.val), '_'; limit=2)[2])
