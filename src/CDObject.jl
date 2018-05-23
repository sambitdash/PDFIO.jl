export CDTextString, CDDate, CDRect

"""
```
    CDTextString
```
PDF file format structure provides two primary string types. Hexadecimal string `CosXString`
and literal string `CosLiteralString`. However, these are mere binary representation of
string types without having any encoding associated for semantic representation.
Determination of encoding is carried out mostly by associated fonts and character maps in
the content stream. There are also strings used in descriptions and other attributes of a
PDF file where no font or mapping information is provided. This represents the string type
in such situations. Typically, strings in PDFs are of 3 types.

1. Text string
    a. PDDocEncoded string - Similar to ISO_8859-1
    b. UTF-16BE strings
2. ASCII string
3. Byte string - Pure binary data no interpretation

1 and 2 can be represented by the `CDTextString`. `convert` methods are provided to
translate the `CosString` to `CDTextString`
"""
const CDTextString = String

using Base.Dates
using Base.Dates.CompoundPeriod
using Rectangle

"""
```
    CDDate
```
Internally represented as string objects, these are timezone enabled date and time objects.

PDF files support the string format: (D:YYYYMMDDHHmmSSOHH'mm)
"""
struct CDDate
    d::DateTime
    tz::CompoundPeriod
    ahead::Bool
    CDDate(d::DateTime, tz::CompoundPeriod, ahead::Bool = true) =
        new(d, tz, ahead)
end

const CDDATE_REGEX =
    r"D\s*:\s*(?<dt>\d{12})\s*(?<ut>[+-Z])\s*((?<tzh>\d{2})'\s*(?<tzm>\d{2}))?"

"""
```
    CDDate(s::CDTextString)
```
PDF files support the string format: (D:YYYYMMDDHHmmSSOHH'mm)
"""
function CDDate(str::CDTextString)
    m = match(CDDATE_REGEX, str)
    m === nothing && error("Invalid date format in input")
    ut, tzh, tzm = m[:ut], m[:tzh], m[:tzm]

    tzhr = tzh === nothing ? Hour(0) : Hour(parse(Int, tzh))
    tzhm = tzm === nothing ? Minute(0) : Minute(parse(Int, tzm))
    
    tz = tzhr + tzhm
                          
    ahead = (ut != "-")
    return CDDate(DateTime(m[:dt], dateformat"yyyymmddHHMMSS"), tz, ahead)
end

function Base.show(io::IO, dt::CDDate)
    show(io, dt.d)
    dt.tz == Minute(0) && return print(io, " UTC")
    print(io, dt.ahead ? " + " : " - ")
    print(io, dt.tz)
end

"""
```
    CDRect
```
An `CosArray` representation of a rectangle in the lower left and upper right point format
"""
const CDRect = Rect
