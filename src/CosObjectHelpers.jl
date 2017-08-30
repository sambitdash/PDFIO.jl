using ..Common

import Base: convert

using StringEncodings

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
        str = transcode(String, utf_16_arr)
    else
        # Assume PDFDocEncoding (ISO-8859-1)
        str = StringEncodings.decode(buffer, "ISO_8859-1")
    end
    return CDTextString(str)
end

convert(::Type{CDTextString}, lstr::CosLiteralString) =
    CDTextString(StringEncodings.decode(lstr.val, "ISO_8859-1"))

convert{T <: Number}(::Type{T}, i::CosInt) = T(get(i))

convert{T <: Number}(::Type{T}, f::CosFloat) = T(get(f))

convert(::Type{CDRect}, a::CosArray) = CDRect(a...)

convert{T <: CosString}(::Type{CDDate}, ls::T) = CDDate(CDTextString(ls))

convert(::Type{CDTextString}, name::CosName) = CDTextString(split(String(name.val),'_')[2])
