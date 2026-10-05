# Durable cooking save receipt

`extended_persistence.save_codec_receipt` is an additive low-level full-bundle
writer. It uses the existing `encode_codec` and actual `atomic_file.publish`
path, retains the same affine state and world lease, and returns the existing
response plus a typed `SaveCompletion`.

Only `atomic_file.Durable` produces `DurablyCommitted`. An encoding failure,
`NotPublished`, or `PublishedUnsynced` returns `NotCommitted`. The JSON response
still follows `persistence.published`: published-but-unsynced is a successful
response with `published=true` and `durable=false`. It does not authorize a
durable cooking journal acknowledgement. Existing writer APIs are unchanged.

Like `save_codec`, this entry point assumes its caller has admitted the save,
observed the peer and advanced the request's Session once. The cooking Session
keeps its existing argument/capability and player-record checks, performs that
observation and increment, then invokes this writer without re-entering the
request dispatcher. Re-entering the dispatcher would advance the sequence
twice. The journal's immutable `saved_view` is only a prospective file image;
its live affine state remains unchanged until the actual writer returns
`DurablyCommitted` for the full bundle.

The original checker passed the complete changed writer module and its imports
in 1.2576 seconds: 1,455 declarations, no holes, no declaration selection or
map/order replacement. See `evidence/cooking-durable-writer-source-001.json`.
This receipt verifies typing and input identity. It does not execute the new
writer, establish an actor save acknowledgement, or claim an interrupted-write
crash result; those require the coherent live consumer.
