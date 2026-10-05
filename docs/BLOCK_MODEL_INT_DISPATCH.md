# Block-model integer scanner dispatch

`block_model.int_scan_admitted` preserves its original signature and numeric
semantics. Five character tests now use `U32.is_eq` followed by Bool dispatch:
minus, plus, point, lower `e` and upper `E`. Stage zero and one also use Bool
tests. A nonrecursive helper transfers the next admission flag, stage and
existing `IntToken`; a structural String/owner matcher continues the scan.
This accommodates Bend's restriction on destructuring computed values without
restoring a higher-order continuation. Refused admission still stops immediately,
including when more text remains. No code outside this scanner section changed.

The retained parent trace `build/item-entity-render-native/producer-phase.json`
records a 2,048 MiB Node-heap failure before C emission: exit -6 in 17.11 seconds,
sampled peak RSS 2,311,225,344 bytes. Its observational compiler copy located the
active `file_book` reachability/type analysis at the old scanner. This diagnosis
does not establish that every renderer compiler blocker is resolved.

The changed module passes the original checker in 1.00 seconds. Ten connected
laws pass the independent kernel in 0.14 seconds with no exclusions. They cover
all five special-character transitions, refusal for arbitrary remaining text,
end-of-input digit reversal and complete token metadata retention, and the
three representative digit-stage transitions. These are stated scanner laws,
not a whole-parser equivalence theorem.

The existing `tests/block_model.bend` observer was rebuilt through the already
verified private producer, with the unchanged original checker and original
compiler pins. Original whole-Book checking plus one C emission took 7.31
seconds; `/usr/bin/clang -O3` took 4.65 seconds. The 75 loaded source/foreign
inputs remained unchanged. This is a focused measurement, not a controlled
whole-renderer speedup.

The changed native observer passes all 17 affected cached 26.3 Java model cases
and both exact exponent-limit refusal records. The separately pinned, unchanged
cached blockstate observer passes its 28 Java cases and two refusals, retaining
the existing combined 45 + 4 corpus without another blockstate build. Accepted
cases compare the complete existing Java success projection; Java rejections
compare status, while the two bounded model refusals compare exact error text.
No full renderer or Generic client was built for this checkpoint.

Evidence is in `evidence/block-model-int-dispatch-native-001.json`. Two genuine
parser failures and one law-pattern diagnostic remain under
`build/block-model-int-dispatch`; no failed attempt was rewritten as a pass.
Run the focused corpus with the existing binary using
`python3 tools/test_block_model_int_dispatch.py --binary PATH --work FRESH_DIR`.
The helper uses the existing bounded process owner and pinned Java corpus.
Independent export/kernel commands and exact term pins are retained under
`build/block-model-int-dispatch/proof-001`.
