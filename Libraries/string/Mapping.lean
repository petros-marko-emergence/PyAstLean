import Libraries.string.StringDef

namespace Libraries.string

/-- Map supported `string` module members (constants) to their Lean runtime values. -/
def pythonStringMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "ascii_lowercase" => some ``Libraries.string.pyStringAsciiLowercase
  | "ascii_uppercase" => some ``Libraries.string.pyStringAsciiUppercase
  | "ascii_letters"   => some ``Libraries.string.pyStringAsciiLetters
  | "digits"          => some ``Libraries.string.pyStringDigits
  | "hexdigits"       => some ``Libraries.string.pyStringHexdigits
  | "octdigits"       => some ``Libraries.string.pyStringOctdigits
  | "punctuation"     => some ``Libraries.string.pyStringPunctuation
  | "whitespace"      => some ``Libraries.string.pyStringWhitespace
  | "printable"       => some ``Libraries.string.pyStringPrintable
  | _ => none

end Libraries.string
