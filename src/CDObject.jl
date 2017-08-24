export CDTextString, CDDate, CDRect

"""
'''
    CDTextString
'''
PDF file format structure provides two primary string types. Hexadecimal string `CosXString`
and literal string `CosLiteralString`. However, these are mere binary representation of
string types without having any encoding associated for semantic representation.
Determination of encoding is carried out mostly by associated fonts and character maps in
the content stream. There are also strings used in descriptions and other attributes of a
PDF file where no font or mapping information is provided. This represents the string type
in such situations. Typically, strings in PDFs are 3 types.

1. Text string
    a. PDDocEncoded string - Similar to ISO_8859-1
    b. UTF-16BE strings
2. ASCII string
3. Byte string - Pure binary data no interpretation

1 and 2 can be represented by the `CDTextString`. `convert` methods are provided to
translate the `CosString` to `CDTextString`
"""
const CDTextString = String

using TimeZones

"""
```
    CDDate
```
Internally represented as string objects, these are timezone enabled date and time objects.

PDF files support the string format: (D:YYYYMMDDHHmmSSOHH'mm)
"""
struct CDDate
    d::ZonedDateTime
    CDDate(d::ZonedDateTime) = new(d)
end

"""
```
    CDDate
```
PDF files support the string format: (D:YYYYMMDDHHmmSSOHH'mm)
"""
function CDDate(s::CDTextString)
    s = ascii(s)
    if startswith(s, "D:")
        s = s[3:end]
    end
    s = *(split(s,'\'')...)
    format = "yyyymmddHHMMSS"
    if endswith(s, 'Z')
        s = s[1:end-1]
    else
        format *= "zzzz"
    end
    CDDate(ZonedDateTime(s, format))
end

Base.show(io::IO, dt::CDDate) = show(io, dt.d)

"""
```
    CDRect
```
An `CosArray` representation of a rectangle in the lower left and upper right point format
"""
struct CDRect{T <: Number}
    llx::T
    lly::T
    urx::T
    ury::T
end
