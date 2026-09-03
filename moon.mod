name = "moonbitlang/openseek_tui"

version = "0.1.0"

import {
  "bobzhang/jsonl@0.2.0",
  "bobzhang/openseek@0.3.0",
  "bobzhang/openseek_protocol@0.1.0",
  "moonbit-community/displaytext@0.1.5",
  "moonbit-community/tty@0.3.0",
  "moonbitlang/async@0.21.1",
  "moonbitlang/x@0.4.50",
}

readme = "README.md"

repository = "https://github.com/moonbitlang/openseek_tui"

license = "Apache-2.0"

keywords = [ "openseek", "tui", "terminal", "agent" ]

description = "OpenSeek interactive terminal UI: the openseek_tui binary"

preferred_target = "native"

warnings = "+missing_doc+unnecessary_view_op+test_unqualified_package+unused_default_value+implicit_impl_as_method"
