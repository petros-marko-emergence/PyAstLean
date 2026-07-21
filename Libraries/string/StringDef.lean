import Mathlib

namespace Libraries.string

/-! Python's `string` module constants. -/

def pyStringAsciiLowercase : String := "abcdefghijklmnopqrstuvwxyz"
def pyStringAsciiUppercase : String := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
def pyStringAsciiLetters   : String := pyStringAsciiLowercase ++ pyStringAsciiUppercase
def pyStringDigits         : String := "0123456789"
def pyStringHexdigits      : String := "0123456789abcdefABCDEF"
def pyStringOctdigits      : String := "01234567"
def pyStringPunctuation    : String := "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
def pyStringWhitespace     : String :=
  " \t\n\r" ++ String.singleton (Char.ofNat 11) ++ String.singleton (Char.ofNat 12)
def pyStringPrintable      : String :=
  pyStringDigits ++ pyStringAsciiLetters ++ pyStringPunctuation ++ pyStringWhitespace

end Libraries.string
