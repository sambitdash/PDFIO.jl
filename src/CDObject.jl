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

using Dates
using Dates: CompoundPeriod
using Rectangle
using Printf

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
    CDDate(d::DateTime, tz::CompoundPeriod, ahead::Bool = true) = new(d, tz, ahead)
end

const CDDATE_REGEX =
    r"D:(?<dt>(\d\d){2,7})(?<tz>((?<ahead>[+-])(?<tzh>\d\d)('(?<tzm>\d\d))?|Z))?"

"""
```
    CDDate(s::CDTextString)
```
PDF files support the string format: (D:YYYYMMDDHHmmSSOHH'mm)
"""
function CDDate(str::CDTextString)
    m = match(CDDATE_REGEX, str)
    m === nothing && error("Invalid date format in input")
    ut, tzh, tzm = m[:ahead], m[:tzh], m[:tzm]

    tzhr = tzh === nothing ? Hour(0) : Hour(parse(Int, tzh))
    tzhm = tzm === nothing ? Minute(0) : Minute(parse(Int, tzm))
    tz = tzhr + tzhm

    ahead = !(ut == "-")
    return CDDate(DateTime(m[:dt], dateformat"yyyymmddHHMMSS"), tz, ahead)
end

import Base.==
function (==)(d1::CDDate, d2::CDDate)
    d1.ahead == d2.ahead && d1.tz == d2.tz && return d1.d == d2.d
    d1ut = d1.ahead ? d1.d + d1.tz : d1.d - d1.tz
    d2ut = d2.ahead ? d2.d + d2.tz : d2.d - d2.tz
    return d1ut == d2ut
end

import Base.isless
function Base.isless(d1::CDDate, d2::CDDate)
    d1.ahead == d2.ahead && d1.tz == d2.tz && return isless(d1.d, d2.d)
    d1ut = d1.ahead ? d1.d + d1.tz : d1.d - d1.tz
    d2ut = d2.ahead ? d2.d + d2.tz : d2.d - d2.tz
    return isless(d1ut, d2ut)
end

function Base.show(io::IO, dt::CDDate)
    print(io, "D:")
    Dates.format(io, dt.d, dateformat"YYYYmmddHHMMSS")
    dt.tz == Minute(0) && return print(io, "Z")
    print(io, dt.ahead ? "+" : "-")
    tzh = dt.tz.periods[1].value
    tzm = dt.tz.periods[2].value
    tzs = @sprintf "%02d'%02d" tzh tzm
    print(io, tzs)
end

"""
```
    CDRect
```
An `CosArray` representation of a rectangle in the lower left and upper right point format
"""
const CDRect = Rect
