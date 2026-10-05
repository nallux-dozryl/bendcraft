# Initialized component numeric text

`item_component.initial_number_valid(String)` accepts exactly the original four
numeric lexemes: `0`, `1`, `6`, and `7.2000003`. The literal String matcher is
replaced by four `String.eq` predicates. Alternative spellings remain refused;
this is a lexical guard on the manually constructible JSON AST, before the
actual initialized-default comparison. No other component body changed.

The parent resource check retained in
`build/item-entity-render-source/resources-changed005.json` exhausted its
1,536 MiB Node heap after reaching this declaration: exit -6 in 11.39 seconds,
sampled peak RSS 1,749,467,136 bytes. The changed production module passes the
original checker in 1.99 seconds. This narrow result does not certify the
whole renderer resource graph.

Three laws pass the independent kernel in 0.12 seconds: admission of every
observed lexeme, refusal of any text unequal to all four spellings, and refusal
of that numeric AST node before any arbitrary following values in the actual
`initial_values_valid` guard. The refusal premise is four independent string
inequalities, not an assumed decoder result. The exporter checks the original
complete Book, preserves all declarations and checked bodies, and selects
only these three roots, with no exclusions.

The actual Bend default-JS observer passes 47 exact ordered outputs in 4.50
seconds: the four admissions and 43 refusals covering alternate numeric forms,
whitespace, Unicode and injected JSON text. This function-only change does not
require a new native renderer or inventory artifact; prior native checkpoints
retain their earlier source identity. Pins, bounded process cleanup and the
retained parent failure are recorded in
`evidence/item-component-initial-number-001.json`.

Reproduce the source checks with `bend src/item_component.bend --check-only`
and `bend src/item_component_initial_number_laws.bend --check-only`. The focused
helper `tools/test_item_component_initial_number.py` exposes `suite(executor)`;
its executor runs `bend tests/item_component_initial_number.bend --` followed
by the supplied lexeme arguments and returns stdout plus the existing bounded
process receipt. The independent export/kernel commands are retained in
`build/item-component-initial-number/proof-001`.
