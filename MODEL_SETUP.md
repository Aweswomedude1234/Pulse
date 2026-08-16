# Sound Classifier Model Setup

The audio pipeline classifies sound via the `SoundClassifier` protocol. Until a
real Core ML model is dropped in, the app runs on `FakeSoundClassifier` — a
deterministic placeholder that derives a stable label from cheap signal features
(loudness + brightness). It keeps the whole pipeline, radar map, and tests
runnable, but it is **not** real classification. `SoundClassifierFactory.make()`
automatically upgrades to the real model the moment one is present.

## What to drop in

1. **A YAMNet-class model** exported to Core ML as `YAMNet.mlpackage`
   (or `.mlmodel`). Default target: 521 AudioSet labels, 16 kHz waveform input,
   ~0.96 s analysis window.
   - Common source: convert TensorFlow-Hub YAMNet with `coremltools`, or use a
     pre-converted community package. AST / BEATs also work — see "Swapping
     models" below.
2. **`yamnet_labels.txt`** — the 521 class labels, one per line, in model output
   order. Without it the classifier still runs but emits `class N` labels (and
   the `SoundLabelCatalog` category mapping won't fire).

## Adding to the project

1. Drag `YAMNet.mlpackage` into the `PulseIOSAPP` target in Xcode (check
   "Copy items if needed", target membership = PulseIOSAPP). Xcode compiles it
   to `YAMNet.mlmodelc` in the app bundle.
2. Drag `yamnet_labels.txt` into the same target (as a bundle resource).
3. Build. `CoreMLSoundClassifier.init?` will now find the model and the factory
   returns it instead of the fake.

## Verifying the feature names

`CoreMLSoundClassifier` defaults to input feature `waveform` and output feature
`scores`. Different conversions name these differently. If inference silently
returns no results, open the `.mlpackage` in Xcode, read the **Predictions**
tab, and pass the correct names:

```swift
CoreMLSoundClassifier(
    modelName: "YAMNet",
    inputName: "<model input name>",
    outputName: "<model output name>",
    modelSampleRate: 16_000,
    windowSeconds: 0.96
)
```

If your model expects **log-mel input** rather than a raw waveform, add a mel
front-end and extend `InputMode` — the current build ships only `.waveform`
because that matches the common Apple-converted YAMNet.

## Swapping models (AST / BEATs / other)

The pipeline only depends on the `SoundClassifier` protocol, so any model works
as long as:

- It returns per-label scores that `topResults` can rank.
- Its labels are mapped to `SoundCategory` — either they contain the keywords in
  `SoundLabelCatalog`, or you extend that table.

No other pipeline code needs to change.
