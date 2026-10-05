# Closed effect identifier dispatch

`item_component_effects.kind(String)` keeps the original Result API, all 40
effect constructors and identifiers, and the exact `unknown suspicious stew
effect` refusal. It now compares the requested identifier against the unchanged
`kind_name` values using `String.eq`, then branches on Bool. Its fixed registry
contains exactly the previous enum values. The structural lookup evaluates only
the remaining suffix after a failed comparison.

The parent resource-checker failure is retained in
`build/item-entity-render-source/resources-diagnose.json`: the unchanged original
source API exhausted its 1,536 MiB Node heap while checking the former forty
long String patterns in `kind`. The changed production module passes the
original checker in 0.99 seconds. The parent renderer resource consumer remains
a separate changed-source check; this result does not certify that whole graph.

Three connected laws in `item_component_effects_dispatch_laws.bend` pass the
independent kernel. They cover every enum/name mapping and the exact refusal
for arbitrary identifiers absent from every supplied type, including the
complete registered list. The absence premise consists of individual
identifier inequalities; it does not assume the decoder's outcome.

The original CPU builder produced a fresh native observer in 20.23 seconds,
with a verified content-keyed miss and zero retries. Its 209 cases pass in
0.83 seconds: all 40 identifiers, seven additional signed-duration edges, 128
near-match/unknown refusals, and 34 existing receiver cases for 17 observed
26.3 stew recipes through canonical keys and physical NBT. Registry names are
independently crosschecked between the pinned registry table and Java component
reference. The existing receiver compares typed NBT values; this is not a
whole-save or compound-byte-order claim. Duration, JSON/NBT conversion and
component admission bodies remain unchanged.

Exact source, reference, tool, binary and proof-term pins, bounded process
cleanup, and retained diagnostics are recorded in
`evidence/item-component-effects-dispatch-native-001.json`. Reproduce the focused
receiver with `python3 tools/test_item_component_effects_dispatch.py --build`
in a fresh attempt directory; the helper also exposes `suite(executor, work)`
for existing bounded runners. Renderer, pickup and live actor acceptance remain
separate integration obligations.
