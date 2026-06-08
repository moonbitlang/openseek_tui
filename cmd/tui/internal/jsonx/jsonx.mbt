// Lenient field accessors over a decoded `Json` value. Each returns a benign
// default (`None` / `""` / `0` / `false`) when the value is not an object, the
// key is absent, or the value has the wrong shape — so a decoder can read an
// object field by field without a cascade of nested pattern matches.

///|
/// The value at `key`, or `None` when `object` is not an object or has no such
/// key.
pub fn field(object : Json, key : String) -> Json? {
  if object is Object(fields) {
    fields.get(key)
  } else {
    None
  }
}

///|
/// The string at `key`, or `""` when it is absent or not a string.
pub fn string(object : Json, key : String) -> String {
  if field(object, key) is Some(String(text)) {
    text
  } else {
    ""
  }
}

///|
/// The integer at `key`, or `0` when it is absent or not a number.
pub fn int(object : Json, key : String) -> Int {
  if field(object, key) is Some(Number(number, ..)) {
    number.to_int()
  } else {
    0
  }
}

///|
/// Whether `key` is present with the JSON value `true`.
pub fn bool(object : Json, key : String) -> Bool {
  field(object, key) is Some(True)
}
