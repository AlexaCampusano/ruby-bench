# Workflow C: apply rewrites as guarded boot-time patches

This document specifies a general workflow. It is not specific to one
benchmark, one framework or one repository. Workflow C runs against any Ruby
codebase that Workflow A and Workflow B already processed. Appendix A records
the first instance for reference. Nothing in the design depends on the values
in Appendix A.

## Context

Workflow A discovers candidate methods. Workflow B rewrites them per rule,
measures each rule, and attacks the result with a challenge agent. Workflow B
leaves patches, verdicts and generated specs in `tmp/ruby-transpile/`. Nothing
reaches the application.

Workflow C applies that work. Two constraints shape it.

- The rewritten Ruby is fast and hard to read. A developer must never open a
  source file and meet it. So Workflow C does not edit the original method.
- A patch that survives a later edit to its own method is a silent bug. So each
  replacement carries an AST fingerprint of the method it replaces, and it
  declines when the fingerprint does not match.

Workflow B measures each rule alone. A rule often measures `neutral`, which
means no counter cleared its noise band. The compound question stays open: many
methods applied together may clear a band that no single rule cleared. Workflow
C answers it.

Intended outcome:

- The application source stays readable.
- Every eligible rewritten method replaces its original at boot.
- A method that drifted since the transpiler ran keeps its original body.
- One benchmark run reports the compound delta against a fresh baseline.
- The suite passes with the patches on and with the patches off.

## Portability

The repository that motivated this work holds 72 benchmarks. Four are Rails
applications. The rest are plain Ruby programs, gems under test, or scripts.
The Rails path is the minority case.

So the design separates two layers.

- **The core** is host-independent: fingerprint, extraction, `Module#prepend`,
  manifest, and the on/off switch. It needs Ruby and Prism and nothing else.
- **The host adapter** decides only *when* a patch activates. Three adapters
  cover the shapes seen in practice.

Workflow C detects the host shape. It never assumes Rails.

## Inputs

Workflow C consumes the Workflow B artifact directory. It reads:

| Path | Use |
| --- | --- |
| `runs/<rule>/verdict.json` | decision, verdict, failed gate, failing methods |
| `runs/<rule>/patch.diff` | the rewritten source |
| `runs/<rule>/work.json` | allowed paths, original bodies |
| `runs/<rule>/challenge/specs/` | generated behaviour specs |

`RUBY_TRANSPILE_DIR` and `RUBY_TRANSPILE_TARGET` keep their meaning from
Workflow B. Workflow C adds no new environment contract.

Workflow C reads no field that Workflow B does not already write.

## The unit of work is the method

Workflow B decides per rule. Workflow C decides per method.

`select_patches.rb` reads every `verdict.json` and applies three predicates:

- Decision `keep` or `neutral` admits every rewritten method in the rule.
- Decision `reject` with `failed_gate == "tests"` is a correctness rejection.
  It admits every rewritten method except those named in
  `methods_failing_on_candidate`. A clean method in a rule that failed
  elsewhere is still a good method.
- Decision `reject` with no failed gate is a statistics rejection: a gated
  counter regressed. It admits nothing. There is no failing method to exclude,
  and the rewrite is slower than the original, so applying it would work
  against the compound.

Two guards on the correctness case:

- `methods_failing_on_candidate` must be non-empty. An empty list on a tests
  failure means the challenge agent could not attribute the failure. Admit
  nothing from that rule.
- The rule's `narrowable` field, when present, must not be false.

`select_patches.rb` writes `compound/selection.json` holding the admitted rules,
the excluded methods, and the reason for every exclusion.

## Derive the rewritten set from the patch, not from work.json

`work.json.methods` lists the methods a rule was **offered**, not the methods it
**rewrote**. A rule offered 58 candidates may rewrite 13. Treating `work.json`
as the applied set would emit 45 patches that replace a method with itself.

`extract_methods.rb` derives the true set:

1. Copy the repository to a scratch directory.
2. Apply `runs/<rule>/patch.diff` there.
3. Prism-parse each changed file at HEAD and in the scratch copy.
4. A method is rewritten when its canonical AST differs. Canonical means the
   Prism dump with every location stripped, so a reindent alone does not count.
5. A method present in the scratch copy and absent at HEAD is an added helper.
6. Drop the excluded methods. Then drop any helper that no retained method
   calls. Resolve that transitively: a helper that only another retained helper
   calls stays.
7. Stop and report when an added helper's name already exists on the owner at
   HEAD. That is a collision, not a helper.

`work.json` still supplies the allowed-path list and the original body in its
`source` field.

Visibility comes from the same Prism pass over the whole file, not from
`work.json`. The `source` field holds the method body alone. It does not record
whether a `private` or `protected` keyword precedes the definition. A prepended
module must re-apply the original visibility, or the patch makes a private
method public and changes the class contract.

## The fingerprint

The guard answers one question: is this method the same method the transpiler
read?

```
fingerprint = SHA256(
  owner + singleton_flag + name + parameter_list + canonical_ast
)
```

`canonical_ast` is the Prism node dump with locations stripped. A comment
change, a reindent, or a moved method does not invalidate the patch. A changed
body, a changed parameter list, or a rename does.

Prism ships inside Ruby 3.4 and later. The guard adds no dependency.

Two tiers keep boot cheap:

1. Compare the SHA of the whole file against the recorded digest. A match
   accepts every method in that file with no parse.
2. Parse with Prism and check per-method fingerprints only when the file digest
   differs.

An unmodified checkout pays one `File.read` and one SHA per patched file.

## Replacement

`Module#prepend` performs the replacement in every host shape. An anonymous
module carries the rewritten body, so the original stays reachable through
`super` and the original `Method` object stays intact.

- Instance method: `Owner.prepend(mod)`.
- Class method: `Owner.singleton_class.prepend(mod)`.
- Private or protected original: the module re-applies the same visibility.

Refinements are not an option. They do not apply to code that already loaded,
and a framework calls the patched method outside the refinement's lexical
scope.

`ENV["TRANSPILE"] == "0"` skips every prepend. This is the A/B switch for
measurement and the one-variable rollback.

## Host adapters

The adapter decides when a patch activates. `detect_host.rb` picks one.

**Adapter 1: plain Ruby, script or gem.** No framework. The generated file
loads through an explicit `require` from the entry point, or through
`RUBYOPT="-r<file>"`. Constants are loaded by the time the patch file runs, so
each patch prepends immediately. This covers the large majority of targets.

**Adapter 2: gem under test.** The patch file must load after the gem and
before the benchmark. The adapter emits a require that the benchmark harness
loads, and asserts the owner constant is already defined. A missing constant is
an error, not a deferral: a gem does not autoload.

**Adapter 3: Rails with Zeitwerk.** Constants may not be loaded when the patch
file runs. Eager loading differs by environment, so a blanket
`after_initialize` hook would force every patched class to autoload in an
environment that does not eager-load, and that changes boot behaviour.

So each patch registers itself this way:

- `Object.const_defined?(owner)` is true — prepend immediately.
- Otherwise — `Rails.autoloaders.main.on_load(owner) { prepend }`.

Files loaded by an explicit `require` outside the autoload paths may never
trigger `on_load`. The `const_defined?` branch covers them.

## Where the generated files live

Placement follows the host's existing convention for load-time patches. The
adapter reads it; the workflow does not impose one.

The general layout:

- `<patch_root>/transpiled.rb` — the runtime. Fingerprint check, prepend,
  visibility, logging, `TRANSPILE` switch.
- `<patch_root>/transpiled/<owner>.rb` — one file per patched owner.
- `<patch_root>/transpiled/manifest.json` — owners, method names, fingerprints,
  file digests, visibility, source rule.

`<patch_root>` resolves per adapter:

- Plain Ruby or gem: the directory the entry point already requires from,
  usually `lib/`.
- Rails: `lib/`, with the autoloader told to ignore the new directory. Follow
  whatever the target already does for load-time patches. A Rails app that
  keeps patch code in `lib/` and ignores it in an initializer gives the exact
  pattern to copy, including the require.

The adapter may need one line in one pre-existing file to register the ignore
or the require. That line is the only edit Workflow C makes to a pre-existing
`.rb` file. The purity gate enforces it.

## Deterministic scripts

Five new scripts. Two existing scripts run unchanged.

| Script | Arguments | Writes |
| --- | --- | --- |
| `detect_host.rb` | none | `compound/host.json` |
| `select_patches.rb` | none | `compound/selection.json` |
| `extract_methods.rb` | `SELECTION_JSON` | `compound/methods.json` |
| `emit_patches.rb` | `METHODS_JSON HOST_JSON` | patch files, `compound/emitted.json` |
| `verify_compound.rb` | `TEST_COMMAND` | `compound/verify.json` |

Reused with no change:

- `capture_baseline.rb` from the discover skill. It calls `Process.spawn` with
  an env hash, which merges into the inherited environment. So `TRANSPILE=0`
  and `TRANSPILE=1` reach the benchmark with no edit to that script.
- `compare_metrics.rb` from the rewrite skill. It reads `verify.json` and
  rejects when it is absent. `verify_compound.rb` emits the same keys: `ok`,
  `failed_gate`, `tests`, `test_command`, `changed_files`.

LLM agents: **1 required, 1 conditional.**

- One agent runs the scripts, installs the specs, runs the gates and the
  measurement. Workflow scripts have no filesystem access, so at least one
  agent must exist.
- A second agent runs only when `extract_methods.rb` reports a helper collision
  or a method it cannot attribute. It triages that case alone.

No agent writes a rewritten method body. Every body comes from `patch.diff`
through Prism. This keeps the workflow cheap and repeatable.

## The generated specs

Install every generated spec from `runs/*/challenge/specs/` into the target's
spec directory.

Install them all, including specs from rules that contributed no method, and
including examples that cover excluded methods. An excluded method keeps its
original body, so its examples assert HEAD behaviour and pass. They also become
a regression guard: if a later run admits that method, the specs fail.

The specs pin HEAD behaviour. Every example must pass with `TRANSPILE=0` and
with `TRANSPILE=1`. A difference between the two runs is a divergence the
patches introduced.

Install the specs even when a target has no suite of its own. In that case the
generated specs are the only correctness evidence, and the workflow reports
`review`, never `keep`, matching Workflow B's rule.

## Gates

| Gate | Rejects |
| --- | --- |
| purity | a pre-existing `.rb` modified beyond the single adapter line |
| syntax | `ruby -c` fails on an emitted file |
| activation | fewer patches applied than `methods.json` holds |
| tests off | suite fails with `TRANSPILE=0` |
| tests on | suite fails with `TRANSPILE=1` |
| drift drill | a deliberately edited method still accepts its patch |

The drift drill proves the guard works rather than assuming it. The agent adds
one statement to one patched method in a scratch copy, boots, and confirms that
patch declines while every other patch applies.

## Drift behaviour, and a recommendation

The requested behaviour is skip, record, and no failure in the next workflow,
with a request for a recommendation. I recommend it, with one qualification.

At runtime the answer is clear. A declined patch logs one line and leaves the
original method. It never raises. A guard that raises turns a stale patch into
an outage, and the original method is always correct.

The qualification concerns Workflow C's own report, not the runtime. If most
patches decline, the benchmark measures a fraction of the work. Reporting that
as the compound result would be false. So:

- The activation gate does not fail the workflow on a decline.
- The measurement covers only the patches that applied, and the report states
  the applied count beside the delta.
- `compound/stale.json` lists every declined method with its expected and
  actual fingerprint.

`stale.json` is the seam that feeds re-discovery. Workflow A reads it and
rescans only those methods. Auto-triggering Workflow A from inside Workflow C
stays out of scope; the artifact is enough to drive it by hand or from a later
workflow.

One exception applies to the first run against a given HEAD. The patches derive
from that HEAD, so zero declines are expected. A decline there means the
fingerprint is wrong, not that the code drifted. The verification section
treats it as a bug.

## Verification

Run these against any target. Expected values are derived from the target's own
artifacts, not fixed.

Host detection:

1. `compound/host.json` names one adapter. Confirm it matches the target: a
   Rails app must not select the plain-Ruby adapter.

Selection and extraction:

2. `compound/selection.json` admits every `keep` and `neutral` rule, admits
   correctness-rejected rules minus their named failing methods, and excludes
   every statistics-rejected rule with reason `statistics`.
3. `compound/methods.json` holds fewer methods than the sum of
   `work.json.methods`, because it counts rewrites and not candidates. Confirm
   the difference is real by spot-checking one rule against its `patch.diff`.
4. Every method in `methods.json` appears in exactly one rule. An overlap means
   two patches target one method, and the workflow must stop.

Emission:

5. `git status` lists new files under the patch root and the spec directory,
   plus at most one modified pre-existing file. Any other modified `.rb` fails
   the purity gate.
6. `ruby -c` passes on every emitted file.

Activation:

7. Boot with `TRANSPILE=1` and read the manifest report. Every method in
   `methods.json` applies. A decline on the first run is a fingerprint bug.
8. Confirm every method that was private or protected at HEAD keeps that
   visibility after the prepend.
9. On the Rails adapter, boot an environment that does not eager-load. Confirm
   no patched class autoloads before its first use.

Correctness:

10. Run the full suite with `TRANSPILE=0`. Pre-existing plus generated examples
    pass.
11. Run the full suite with `TRANSPILE=1`. The same examples pass. A failure
    here is a divergence the compound introduced that no single rule exposed.
12. Run the drift drill. The edited method declines, the rest apply, the suite
    passes.

Compound measurement:

13. Capture a fresh baseline with `TRANSPILE=0`, then the candidate with
    `TRANSPILE=1`, in one session, same `jit`, same `measureRepeats`, same
    `resetCommand`. `capture_baseline.rb` already discards the first run.
14. Run `compare_metrics.rb` against the two. Record the decision.
15. Compare the compound delta against the per-rule deltas from Workflow B.
    Record whether the methods together clear a band that none of them cleared
    apart. `neutral` is a valid answer and settles the compound question either
    way.

Reproducibility:

16. Re-run `select_patches.rb`, `extract_methods.rb` and `emit_patches.rb`. The
    emitted files must be byte-identical. A generator that is not reproducible
    cannot be trusted to decline correctly.

## Out of scope

- No hunk-level patch assembly. Hunks do not map to methods. A hunk can carry
  an added helper, and two nearby methods merge into one hunk once a rewrite
  grows them.
- No change to an original method body in application source. That is the point
  of the workflow.
- No change to `compare_metrics.rb` or `capture_baseline.rb`.
- No re-run of Workflow A or B. Workflow C writes `stale.json` and stops.
- No statistics-rejected rule. Its rewrite is slower than the original.
- No refinements.

## Appendix A: the first instance

These values come from one Workflow B run against `benchmarks/lobsters`. They
illustrate the predicates. They are not part of the specification, and a
different target produces different values.

| Rule | Decision | Reason | Methods admitted |
| --- | --- | --- | --- |
| `hoist_repeated_work` | keep | confirmed | 13 |
| `reduce_dynamic_dispatch` | neutral | confirmed | 7 |
| `direct_loops` | reject | correctness | 5 of 7 |
| `move_cold_code_out` | neutral | confirmed | 1 |
| `reduce_block_and_proc_allocation` | neutral | confirmed | 1 |
| `remove_intermediate_objects` | reject | statistics | 0 |

Observations from that run that informed the design:

- 27 methods admitted across 5 rules and 12 files, with zero method-level
  overlap. Four files carry rewrites from more than one rule. The boot-patch
  model composes where a textual merge would conflict.
- `hoist_repeated_work` was offered 58 candidate methods and rewrote 13. This
  is why the applied set comes from the patch and not from `work.json`.
- `direct_loops` failed the tests gate on 2 of 7 methods, named in
  `methods_failing_on_candidate`. The other 5 are admitted.
- `remove_intermediate_objects` regressed `side_exit_count` with a passing
  suite. It contributes nothing.
- Three admitted methods are private. Visibility must be re-applied.
- That target keeps load-time patches in `lib/`, requires them explicitly, and
  tells Zeitwerk to ignore them in an initializer. Adapter 3 copies that
  pattern, which costs one added line in that initializer.
