export CDTextString, CDDate, CDRect

const CDTextString = String

using TimeZones

"""
PDF files support the string format: (D:YYYYMMDDHHmmSSOHH'mm)

"""
@compat struct CDDate
    d::ZonedDateTime
    CDDate(d::ZonedDateTime) = new(d)
end

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

@compat struct CDRect{T <: Number}
    llx::T
    lly::T
    urx::T
    ury::T
end
