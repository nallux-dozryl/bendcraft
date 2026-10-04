# Original Java numeric corpus

Confidence is high for the recorded original Java observations. Candidate native parity remains unverified.

The numeric continuation candidate is checked against 45 inputs whose expected results come from original Minecraft Java 26.3 classes: 35 cases selected from existing, hash-verified executed model/blockstate probes and ten fresh exponent cases executed by the unchanged original blockstate probe. Java accepted 26 inputs and rejected 19. The fresh ten-case Java phase returned zero in 3.881 seconds, using the pinned 41,483,720-byte client JAR with SHA-256 `4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.

The corpus covers fractional truncation, negative values, low-32-bit wrapping, signed boundaries, numeric/string/boolean/null gates, positive and negative exponents, rotation normalization, positive weighted choices and rejected weights. Original input text retains each exponent lexeme. Accepted models use the existing complete parsed projection. Accepted blockstate requests carry the actual observed schema and all real states; their expected projection includes selector order, model choices, dependencies and mapped states. Rejection comparisons concern acceptance status rather than Java/Bend error wording.

The first fresh probe completed Java successfully, then the host extraction failed with `KeyError: wheat`: the broad existing request helper appended unrelated wheat boundary cases despite the narrow probe requesting only the oak-fence schema. That failure is retained. The corrected extraction projects only dispatcher rows with the unchanged existing dispatcher projection. It reused the same successful Java observation file; Java was not repeated.

Reproduce preparation and the original Java execution in a fresh ignored directory:

```sh
python3 tools/generic_resource_world_sample_numeric_original_corpus.py --directory build/generic-resource-world-sample-numeric-original-corpus-NNN
python3 tools/generic_resource_world_sample_numeric_original_corpus.py --directory build/generic-resource-world-sample-numeric-original-corpus-NNN --run-java
```

The `--project-java` option can finish extraction from a preserved successful Java attempt without executing Java again. The public compact receipt is `evidence/generic_resource_world_sample_numeric_original_corpus.json`; the full ignored fixtures are `build/generic-resource-world-sample-numeric-original-corpus-001/{cached-corpus,exponent-corpus}.json`.

This corpus does not establish candidate correctness by itself. The six arbitrary continuation laws, independent kernel verdict, focused generated-C measurements and native comparison remain separate obligations. No whole-parser equivalence, full generic-client build or window acceptance is claimed here.
