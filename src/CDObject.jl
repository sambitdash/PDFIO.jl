export CDTextString, CDDate, CDRect, getUTCTime

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

import Base: ==, isless, show

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
    tz = CompoundPeriod(tzhr, tzhm)
    ahead = !(ut == "-")
    return CDDate(DateTime(m[:dt], dateformat"yyyymmddHHMMSS"), tz, ahead)
end

function Base.show(io::IO, dt::CDDate)
    print(io, "D:")
    Dates.format(io, dt.d, dateformat"YYYYmmddHHMMSS")
    tzp = dt.tz.periods
    np = length(tzp)
    @assert np <= 2
    np == 0 && return print(io, "Z")
    print(io, dt.ahead ? "+" : "-")
    tzh, tzm = 0, 0
    if np == 2
        tzh, tzm = tzp[1].value, tzp[2].value
    else
        p1 = tzp[1]
        p1 isa Hour   && (tzh = p1.value)
        p1 isa Minute && (tzm = p1.value)
    end
    tzs = @sprintf "%02d'%02d" tzh tzm
    print(io, tzs)
end

getUTCTime(d::CDDate) = 
    CDDate(d.ahead ? (d.d - d.tz) : (d.d + d.tz), CompoundPeriod())

Base.isless(d1::CDDate, d2::CDDate) = isless(getUTCTime(d1).d, getUTCTime(d2).d)

Base.:(==)(d1::CDDate, d2::CDDate) = !isless(d1, d2) && !isless(d2, d1)

"""
```
    CDRect
```
`CosArray` representation of a rectangle in the lower left and upper right point format
"""
const CDRect = Rect
