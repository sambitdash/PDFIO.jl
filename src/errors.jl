export  E_EXPECTED_EOF, E_UNEXPECTED_EOF, E_UNEXPECTED_CHAR, E_BAD_KEY,
        E_BAD_ESCAPE, E_BAD_CONTROL, E_LEADING_ZERO, E_BAD_NUMBER, E_BAD_HEADER,
        E_BAD_TRAILER, E_BAD_TYPE, E_NOT_IMPLEMENTED,
        E_INVALID_OBJECT, E_INVALID_PAGE_NUMBER, E_INVALID_PAGE_LABEL,
        E_NOT_TAGGED_PDF, E_INVALID_PASSWORD

# The following errors may be thrown by the reader
const E_EXPECTED_EOF    = "Expected end of input"
const E_UNEXPECTED_EOF  = "Unexpected end of input"
const E_UNEXPECTED_CHAR = "Unexpected character"
const E_BAD_KEY         = "Invalid object key"
const E_BAD_ESCAPE      = "Invalid escape sequence"
const E_BAD_CONTROL     = "ASCII control character in string"
const E_BAD_NUMBER      = "Invalid number"
const E_BAD_HEADER      = "Invalid file header"
const E_BAD_TRAILER     = "Invalid file trailer"
const E_BAD_TYPE        = "Invalid object type"

const E_FAILED_COMPRESSION  = "Data not compressed properly."
const E_DECRYPT_DOCUMENT    = "Unable to decrypt document"
const E_INVALID_CATALOG   = "Invalid document catalog"
const E_INVALID_DATE        = "Invalid date format in input"
const E_INVALID_DELIMITER = "Invalid delimiter character"
const E_INVALID_OBJECT      = "Invalid Object Found"
const E_INVALID_PAGE_NUMBER = "Page number is invalid"
const E_INVALID_PAGE_LABEL  = "Page label is invalid or page label definitions are not present in the document (Table 28 PDF Specification 1.7)"
const E_INVALID_PASSWORD    = "The password supplied to open the document is invalid"
const E_INVALID_CRYPT       = "The crypt handler is not supported"
const E_NOT_TAGGED_PDF      = "PDF file is not tagged"
const E_NOT_IMPLEMENTED     = "Not Implemented"
