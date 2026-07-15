import TypeInfer.PyType

/-!
# Python annotations ↔ `PyType`

`ofAnnotation` reads a type annotation out of the JSON IR, `toAnnotation?` writes one back.
The pre-pass in `annotate_python.py` has already normalised `typing.List[int]` to `list[int]` and
`Optional[X]` to `X | None`, so only the builtin generic spellings need handling here.
-/

namespace TypeInfer

open Lean

private def nodeType? (json : Json) : Option String :=
  (json.getObjValAs? String "node_type").toOption

/-- `typing`'s capitalised spellings, folded onto the builtin ones. -/
private def canonical (name : String) : String :=
  match name with
  | "Int" => "int" | "Bool" => "bool" | "String" | "Str" => "str" | "Float" => "float"
  | "List" => "list" | "Set" => "set" | "FrozenSet" => "frozenset"
  | "Dict" | "Mapping" => "dict" | "Tuple" => "tuple" | "Sequence" | "Iterable" => "list"
  | n => n

/-- Builtin annotation names. Anything else is a user class. `Any`/`object` are the *gradual*
dynamic type — "no static information" — so they read as `.unknown` (⊥), NOT `.any` (⊤, which means
concrete types that genuinely conflict, e.g. an `int | str` union that must be boxed). -/
private def baseTypes : List (String × PyType) :=
  [ ("int", .int), ("bool", .bool), ("str", .str), ("float", .float),
    ("None", .none), ("Any", .unknown), ("object", .unknown),
    ("list", .list .unknown), ("set", .set .unknown), ("frozenset", .set .unknown),
    ("dict", .dict .unknown .unknown), ("tuple", .tuple []) ]

/-- Generic containers written `c[...]`, keyed by the name before the bracket. -/
private def containerOf (name : String) (args : List PyType) : Option PyType :=
  match name, args with
  | "list", [e] => some (.list e)
  | "set", [e] | "frozenset", [e] => some (.set e)
  | "dict", [k, v] => some (.dict k v)
  | "tuple", es => some (.tuple es)
  | "Optional", [e] => some (.opt e)
  | "Union", es => some (PyType.joinAll es)
  | _, _ => none

/-- Read a Python type annotation. Unrecognised shapes are `unknown`, never an error. -/
partial def ofAnnotation (json : Json) : PyType :=
  match nodeType? json with
  | some "Name" =>
      match (json.getObjValAs? String "id").toOption with
      | some id => match baseTypes.lookup (canonical id) with
          | some t => t
          | none => .cls id
      | none => .unknown
  -- A string forward reference: `def f(root: "TreeNode")`.
  | some "Constant" =>
      match json.getObjVal? "value" with
      | .ok (.str s) => ofAnnotation (Json.mkObj [("node_type", .str "Name"), ("id", .str s)])
      | .ok .null => .none
      | _ => .unknown
  -- `typing.List[int]` if the pre-pass left it alone.
  | some "Attribute" =>
      match (json.getObjValAs? String "attr").toOption with
      | some attr => ofAnnotation (Json.mkObj [("node_type", .str "Name"), ("id", .str attr)])
      | none => .unknown
  -- `X | None`, which is how `Optional[X]` reaches us.
  | some "BinOp" =>
      if (json.getObjValAs? String "op").toOption == some "bitor" then
        match json.getObjVal? "left", json.getObjVal? "right" with
        | .ok l, .ok r => PyType.join (ofAnnotation l) (ofAnnotation r)
        | _, _ => .unknown
      else .unknown
  | some "Subscript" =>
      let name := match json.getObjVal? "value" with
        | .ok v => match nodeType? v with
            | some "Name" => (v.getObjValAs? String "id").toOption
            | some "Attribute" => (v.getObjValAs? String "attr").toOption
            | _ => none
        | _ => none
      let args := match json.getObjVal? "slice" with
        | .ok slice =>
            if nodeType? slice == some "Tuple" then
              ((slice.getObjValAs? (Array Json) "elts").toOption.getD #[]).toList.map ofAnnotation
            else [ofAnnotation slice]
        | _ => []
      match name with
      | some n => (containerOf (canonical n) args).getD .unknown
      | none => .unknown
  | _ => .unknown

private def nameAnn (id : String) : Json :=
  Json.mkObj [("node_type", .str "Name"), ("id", .str id)]

private def subscriptAnn (container : String) (args : List Json) : Json :=
  let slice := match args with
    | [a] => a
    | _ => Json.mkObj [("node_type", .str "Tuple"), ("elts", Json.arr args.toArray)]
  Json.mkObj [("node_type", .str "Subscript"), ("value", nameAnn container), ("slice", slice)]

/-- Write a `PyType` back as an annotation node. `none` when the type is not fully known, since
an unknown annotation is worse than no annotation — it would name a type that does not exist. -/
partial def toAnnotation? (t : PyType) : Option Json := do
  match t with
  | .unknown | .any => none
  | .int => nameAnn "int"
  | .bool => nameAnn "bool"
  | .str => nameAnn "str"
  | .float => nameAnn "float"
  | .none => nameAnn "None"
  | .cls n => nameAnn n
  | .list e => subscriptAnn "list" [← toAnnotation? e]
  | .set e => subscriptAnn "set" [← toAnnotation? e]
  | .opt e => subscriptAnn "Optional" [← toAnnotation? e]
  | .dict k v => subscriptAnn "dict" [← toAnnotation? k, ← toAnnotation? v]
  | .tuple es => subscriptAnn "tuple" (← es.mapM toAnnotation?)

end TypeInfer
