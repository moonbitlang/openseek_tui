///|
test "completion item matches label or inserted text case-insensitively" {
  let items = [
    @completion.CompletionItem::new(
      label="/model",
      insert_text="model",
      description="show model",
    ),
    @completion.CompletionItem::new(label="/help", insert_text="help"),
  ]
  let by_inserted = @completion.completion_item_matches(items, "mo")
  assert_eq(by_inserted.length(), 1)
  assert_eq(by_inserted[0].label(), "/model")
  assert_eq(by_inserted[0].insert_text(), "model")

  let by_label = @completion.completion_item_matches(items, "/H")
  assert_eq(by_label.length(), 1)
  assert_eq(by_label[0].insert_text(), "help")
  assert_eq(@completion.completion_item_matches(items, "x").length(), 0)
}

///|
test "exact completion matches rank ahead of longer prefix matches" {
  // Recency-ordered ids where a longer, newer id sorts before the exact one the
  // user typed (the /resume hazard): `abc` must win index 0 over `abcd`, since
  // Enter accepts the first item.
  let items = [
    @completion.CompletionItem::new(label="abcd"),
    @completion.CompletionItem::new(label="abc"),
  ]
  let matches = @completion.completion_item_matches(items, "abc")
  assert_eq(matches.length(), 2)
  assert_eq(matches[0].insert_text(), "abc")
  assert_eq(matches[1].insert_text(), "abcd")

  // A non-exact prefix still matches both, keeping the original recency order.
  let prefix_only = @completion.completion_item_matches(items, "ab")
  assert_eq(prefix_only.length(), 2)
  assert_eq(prefix_only[0].insert_text(), "abcd")
  assert_eq(prefix_only[1].insert_text(), "abc")
}

///|
test "completion model carries open state defensively" {
  let items = [
    @completion.CompletionItem::new(label="deepseek-v4-flash"),
    @completion.CompletionItem::new(label="deepseek-v4-pro"),
  ]
  let model = @completion.Model::open(items~, selected=99)
  items.push(@completion.CompletionItem::new(label="other"))
  assert_true(model.is_open())
  assert_eq(model.selected(), 1)
  let model_items = model.items()
  assert_eq(model_items.length(), 2)
  assert_eq(model_items[0].insert_text(), "deepseek-v4-flash")
  assert_eq(model_items[1].insert_text(), "deepseek-v4-pro")
}

///|
test "closed completion model has no items" {
  let model = @completion.Model::closed()
  assert_true(!model.is_open())
  assert_eq(model.selected(), 0)
  assert_eq(model.items().length(), 0)
}
