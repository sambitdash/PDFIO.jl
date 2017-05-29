export decode

const Filter_ASCIIHexDecode=CosName("ASCIIHexDecode")
const Filter_ASCII85Decode=CosName("ASCII85Decode")
const Filter_LZWDecode=CosName("LZWDecode")
const Filter_FlateDecode=CosName("FlateDecode")
const Filter_RunLengthDecode=CosName("RunLengthDecode")
const Filter_CCITTFaxDecode=CosName("CCITTFaxDecode")
const Filter_JBIG2Decode=CosName("JBIG2Decode")
const Filter_DCTDecode=CosName("DCTDecode")
const Filter_JPXDecode=CosName("JPXDecode")
const Filter_Crypt=CosName("Crypt")

function _not_implemented(stm::CosStream)
  error(E_NOT_IMPLEMENTED)
end

"""
Decodes using the zlib/flate compression
"""
function decode_flate(stm::CosStream)
  print("Ready to decode the flate stream")
end

const function_map = (
   Filter_ASCIIHexDecode => _not_implemented,
   Filter_ASCII85Decode => _not_implemented,
   Filter_LZWDecode => _not_implemented,
   Filter_FlateDecode => decode_flate,
   Filter_RunLengthDecode => _not_implemented,
   Filter_CCITTFaxDecode => _not_implemented,
   Filter_JBIG2Decode => _not_implemented,
   Filter_DCTDecode => _not_implemented,
   Filter_JPXDecode => _not_implemented,
   Filter_Crypt => _not_implemented
)

"""
Reads the filter data and decodes the stream.
"""
function decode(stm::CosStream)
  filename = get(stm, CosStream_F)
  filters = get(stm, CosStream_FFilter)
  if (isa(filters,CosArray))
    error(E_NOT_IMPLEMENTED)
  end
  return function_map[filters](stm)
end
