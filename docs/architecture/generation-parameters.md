# Generation parameters and forms

Image and video configuration share a typed schema and one workbench form. The
dispatcher remains the only route selector. `generationSchemaFor` resolves the
effective wire and serving capabilities; schemas never import the dispatcher.
The encoder target receives the same capabilities. Video wires sharing a model
family still have separate vocabularies: family equality is not wire compatibility.

## Declarations and extension

Model declarations are `generation/profiles/*_profiles.dart`, parts of
`model_capabilities.dart`. Classification stays in the existing layer-3 files.
`ModelCapabilities.profiles` is the complete registry used by generation schemas
and billing-condition vocabulary enumeration. `idRoutedTables` remains a legacy
classification/testing compatibility list, not a complete registry.

`GenerationParam` adapts existing `ParamSpec`, `ImageSizeRules`, pixel tables and
size vocabularies. Typed values distinguish unset, explicit upstream auto,
booleans, integers, decimals, choices and sizes. Legacy strings exist at the
preference/encoder boundary; they are not the versioned request's value types.
Required defaults such as MiniMax duration and DashScope audio are preserved.

`protocols/generation_contract.dart` declares wire input restrictions.
`GenerationSchema` composes these with model parameter and reference limits.
`GenerationProfiles.byWire` explicitly lists compatible native alias profiles;
it does not offer protocols or select an endpoint. Provider menus still narrow
the available wire in the dispatcher. A stored incompatible profile produces
a visible diagnostic and blocks initial submission. Unknown aliases keep the
existing conservative wire fallback, which is not verification of their actual
model capabilities. Chat aliases keep their existing descriptor and dialect;
they have no speculative profile overrides.

An alias profile is an optional `generation_profile.<model-row-id>` setting.
AppState caches it for UI; the injected database supplies it to the config resolver
and task snapshot writer. Model settings save the identity only. No schema
migration or persisted derived capability copy is needed.

To add a model version, extend its profile module, register its stable identity,
and update the permitted layer-3 matching rule. Reuse existing parameter types
and encoding where possible. Add a wire contract or encoder change only when
the wire differs. Test defaults, compatible routes, payloads and billing output.

## Draft, validation and media

Draft values survive model/operation switches. Effective requests exclude
inactive fields and visibly fix required fields. Seedream layers hide aspect
ratio and group count; transparent editing requires one source with an alpha
channel and fixes PNG. The source requirement is shown in the form and checked
against decoded bytes in an isolate before transport. Transparent source images
bypass optional JPEG compression, which would destroy their required alpha.

The video UI keeps conflicting inputs removable and shows localized reasons.
xAI hides an empty last-frame slot; a previously selected unsupported last frame
stays visible for removal. Frames/reference exclusivity comes from the wire
declaration. Shared non-UI validation rejects conflicting, excessive, unreadable
and explicitly invalid inputs before paid submission. Protocol defensive checks
remain for direct protocol callers. Supported keys are checked against the
complete registry; undeclared generation parameters are not treated as metadata.

Dependencies are bounded operation rules, not arbitrary expressions; there is
no dependency graph to evaluate or cycle to schedule. General expression/JSON
form languages and speculative new media types are intentionally excluded.

## Task and preference compatibility

New image/video tasks contain `parameters.generation`, codec version 1:
prompt, operation, typed values, role-tagged media, model/channel row identities,
effective protocol, profile identity and schema version. Application metadata
(output path/prefix, compression, retries, provenance) stays outside this object.
`GenerationExecutionContext` holds runtime cancellation/abort controls and is
never serialized. Credentials resolve at execution time.

`generationTaskOptions` is a temporary compatibility view for encoders, billing
and task details. It is not persisted beside the snapshot. Nested intent owns
prompt/media/values; old flat tasks retain their old read path. Image execution
uses snapshot media rather than an independently editable generic path list.
New tasks queued by a legacy model-ID string resolve to a concrete stored row.

Before initial submission, model/channel row, vendor, protocol, profile and schema
must still match. Credentials and endpoint changes within that same contract
are compatible. Changed capabilities/configuration fail before a new request.
Accepted video jobs resume using persisted operation name/surface without
revalidation or resubmission. Settlement reads the request's compatibility view;
actual reported outputs, sent input counts and reported costs retain precedence.

`GenerationPreferences` namespaces drafts by model row (ID fallback for unsaved
models), channel, effective wire and operation. The mode selector is shared by
operations within that model/wire so switching back finds parked values. The key
prefix is a storage-codec namespace, not a capability-schema reset version.
Old family keys are read-only fallback seeds; new writes never overwrite them.
Invalid stored drafts remain stored while the form shows a supported default
with a localized explanation. JSON evolution uses existing settings/task columns.

## Form ownership and visual continuity

`screens/workbench/widgets/generation_params/` belongs to one feature, covering
both image and video. `GenerationParamPanel` builds field shells and conditional
states; `ParamPresentation` controls editor/span hints; `ParamEditorRegistry`
provides the reusable dropdown, segmented, slider and specialized size adapters.
Hosts may override presentation or one editor without copying either form.
Editors take typed values, labels and callbacks, with no model/provider/DB lookup.
Missing editors show a localized error. Keep registry coverage tests current.

The form reuses existing App controls, size picker, token spacing, theme, font
and glass settings. No new theme or shell primitive is introduced. Fixed fields
exclude pointer and keyboard interaction and expose disabled semantics. Stable
field keys preserve editor identity; narrow available widths stack paired fields.
Labels and diagnostics live in `GenerationParamTexts` and all four locale sources.
Where a spec offers both `not_set` and `auto`, the former is labeled **Default**
and the latter **Auto**, preserving both wire values without duplicate labels.

Review the real workbench harness plus `generation_params_shots_test.dart`, which
covers 390/834/1024/1440 widths, light/dark, four locales and all eight accent seeds.
The specimen captures complement real screens; neither desktop test proves
Android/iOS native navigation or live upstream support. Harnesses write PNGs
without pixel assertions; inspect images and printed exceptions. Behavior,
payload, persistence, routing and billing tests provide the regression gates.
