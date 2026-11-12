# Experimental GNOME 51 color adapter — fresh checks

This is new 51 application work, not a replay of the closed50constructor or standalone installed-library probes.
`prepare.py` copies whole current production declarations and the full `color51.odin` declaration section unchanged;
only package/import headers are selected for the new fixture. Older useful constructor assertions were copied as
new unscored tests against this changed path; old inputs/results/drivers remain untouched and are not invoked.

The actual adapter owns a newly constructed transform through preflight, shader installation and existing-layer
validation; its CPU pipeline/list/ops are borrowed and never independently unreferenced. Both directions enter the
unchanged candidate/swap/teardown transaction. 51 uniforms install with the transform; 50's updates remain conditional.
Unknown operations, invalid sizes, cumulative upload scratch over64MiB, missing layers, non2D textures or wrong
size fail before configuration publication. Streaming enumeration has no fixed collected-layer capacity; signed
layer-index conversion is guarded. The64MiB bound is per-transform upload scratch, not total CPU/GPU/compositor use.

**Both LUT and curve use 2D textures:** LUTsize×size², curve size×1; no invented3D depth query. Layer op-index+10,
texture shapes and known operation set come from retained51reference text, not authenticated effective Pika sources.
They still need actual-library/application rendering validation; rejecting an unknown operation is not universal support.

The fixture uses independently typed IDs, sparse out-of-order existing layers, forbidden default-producing getters,
borrowed-owner checks, retained texture refs, wrong resource/size/unknown/op-upload failures in both directions,
late failure with an old live configuration, cache/retry/HDR/order/teardown checks and literal upload-boundary cases.
It is NOT a GPU, library ABI, shader/transform correctness, full-app, HDR-output, deployment or speedup witness.

Build/test commands and actual counts belong to the fresh bounded owner/scope, not old drivers or broad CTest.
Source extension metadata remains50; experimental CMake option is off by default. No install/extension enable is part
of these checks. Exact existing compile-time and runtime parent-layout guards remain unchanged.
