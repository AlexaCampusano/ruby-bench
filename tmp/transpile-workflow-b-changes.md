# Handoff: Workflow B measurement and verification changes

Written 2026-08-05 from a Workflow B run on `ruby-bench/benchmarks/lobsters`.
All paths below are relative to `~/src/github.com/Shopify/ruby-infra`.

The run finished 8 rules: 7 `reject`, 1 `review`; 7 `overturned`, 1 `unproven`;
zero `keep`. Every one of those verdicts is unsound. Two independent faults made
the run incapable of producing a valid result, and both are fixable.

| File | Change |
|------|--------|
| `.claude/workflows/ruby-transpile-rewrite.js` | worktree base ref, repeats, cache reset, specs replace probes |
| `plugins/.../ruby-transpile-discover/scripts/capture_baseline.rb` | repeated runs, discarded warm-up, median |
| `plugins/.../ruby-transpile-rewrite/scripts/compare_metrics.rb` | measured noise band per counter |
| `plugins/.../ruby-transpile-rewrite/scripts/verify_rewrite.rb` | reject an empty suite; allow new test files; visibility check |
| both `SKILL.md` files | document the above |

`plugins/...` is `plugins/ruby-infra-toolkit/skills/`.
`~/.claude/skills/ruby-transpile-discover` and `~/.claude/skills/ruby-transpile-rewrite`
are symlinks into that directory. Edit the originals.

---

## 1. Fault one: the worktrees had no test suite

Both agents run with `isolation: 'worktree'`. A worktree branches from
`origin/<default-branch>` by default, not from local `HEAD`.

On this machine:

- local `HEAD` is `d7bf2b0`, which added `benchmarks/lobsters/spec/` (49 tracked
  files) and `.rspec`, and changed `app/models/user.rb`
- `origin/main` is `faf8288`, which has zero lobsters spec files

So every agent worktree checked out code without the specs. The configured test
command `bundle exec rspec` printed `No examples found. 0 examples, 0 failures`
and exited 0. Gate 4 recorded `tests: "pass"` for all 8 rules while executing
nothing.

The challenge agents caught this and said so. From the `direct_loops` verdict:

> My tripwire prepended a raising module to both singleton methods and reported
> `TRIPWIRE VOTE_LOADED=false METHOD_CALLED=false` while the suite still passed,
> so the suite never even loads the Vote class. The tests gate in result.json is
> vacuous.

The `hoist_repeated_work` agent ran the same tripwire across 9 methods and got
`ADV_TRIPWIRE installed on: []`. Both agents added a positive control and
confirmed the tripwire itself works.

**Two fixes, both needed.**

*Configuration.* Set `worktree.baseRef` to `head` so worktrees branch from local
`HEAD`. Otherwise any work not yet on `origin/main` is invisible to every agent,
including the code under study.

*Code.* `verify_rewrite.rb` must fail gate 4 when the suite runs zero examples.
Its own comment at lines 218-220 already states the principle:

> Every branch names a suite directory. `bin/rails test` with no test directory
> runs zero tests and still exits zero. That reads as a pass and lets a rewrite
> reach `keep` with nothing having executed it, so the directory has to exist.

That guard lives inside `detect_test_command` and only runs when no command was
given. An explicit `TEST_COMMAND` from the driver skips the probe entirely and
therefore skips the guard. Move the check out of the probe: before running the
command, assert that the suite directory exists in the target; after running it,
parse the output for a zero-example result and fail the gate. Add
`tests: "empty"` as a distinct value so `compare_metrics.rb` can reject rather
than pass it through as `"pass"`.

---

## 2. Fault two: the benchmark was measured in three different states

Unchanged HEAD, 9 runs in one checkout:

| State | allocations | side_exit_count |
|-------|-------------|-----------------|
| first run after the machine idles | 20,043,424 | 100,171 |
| Workflow A baseline, 2026-08-04 | 20,043,735 | 100,196 |
| cold, `tmp/cache` deleted | 20,044,126 | 93,446 |
| warm, 6 runs | 19,987,502 – 19,987,998 | 94,769 – 94,902 |

Two causes:

- `tmp/cache` is a Rails file store that survives the process. In lobsters it
  holds 2 entries, `users_tree_1003` and `user%3A12%3Aunread_replies`. Run 1
  writes them, run 2 reads them. Worth -0.28% on allocations and +1.4% on side
  exits.
- The first benchmark run after the machine idles reads about 7% more side exits
  than a second cold run. The Workflow A baseline is one of those runs.

Each rewrite agent's candidate measurement came out warm; each challenge agent's
fresh-HEAD measurement came out cold. The driver deletes the worktrees, so the
exact reason each one was warm or cold is no longer recoverable. The cold-warm
gap itself is measured and reproducible, and it is enough to explain the result:

| Rule | challenge HEAD | candidate | delta |
|------|---------------|-----------|-------|
| direct_loops | 93,316 | 94,837 | +1.63% |
| reduce_block_and_proc_allocation | 93,331 | 94,821 | +1.60% |
| reduce_dynamic_dispatch | 93,338 | 94,759 | +1.52% |
| reduce_thin_helper_calls | 93,375 | 94,794 | +1.52% |
| remove_intermediate_objects | 93,373 | 94,758 | +1.48% |
| stable_object_shapes | 93,373 | 94,749 | +1.47% |

Eight different patches, touching different files, cannot land within 0.09% of
each other. `move_cold_code_out` is the control: its agent measured both sides in
the same cache state, got 94,820 against 94,826, and returned `neutral`.

Warm against warm, the true noise floor is 0.14% on `side_exit_count` and
0.0025% on `allocations`. The fixed 0.5% band is 200 times the observed
allocation noise. It filed a real -0.30% allocation win as noise.

The `hoist_repeated_work` challenge agent reached the same conclusion
independently. Its own same-machine pair reported `side_exit_count` -0.01%
(94,750 to 94,739, verdict `same`) against the claimed -6.84%, and kept
`allocations` at -0.93%.

---

## 3. capture_baseline.rb — repeated runs

**Current.** One `Process.spawn` of the benchmark, one probe document, one
`baseline.json`.

**Change the interface** to:

    capture_baseline.rb BENCH.rb [yjit|zjit|none] [REPEATS]

`REPEATS` defaults to 3. The script runs the benchmark `REPEATS + 1` times and
discards the first result. The discarded run executes exactly like the others;
only its probe output is thrown away.

**Change `baseline.json`** to add three keys and keep every existing key:

- `repeats` — the integer used.
- `runs` — an array of the kept probe documents, in order. Each entry keeps
  `wall_time_s`, `cpu_time_s`, `gc`, and the JIT `counters`.
- `spread` — a hash of counter name to `(max - min) / median`, computed over the
  kept runs, for every numeric counter.

Set the existing `metrics` and `yjit` / `zjit` keys to the **per-counter median**
across the kept runs. Compute each counter's median independently. Do not pick
one whole run. Derive `top_exits` from the median counters.

Keep the top-level shape identical so `compare_metrics.rb` continues to read
`metrics.allocations` and `yjit.side_exit_count` without a branch.

**Why.** The discarded first run normalizes the cache state and absorbs the
first-run-after-idle effect. The median resists a single contended run. The
spread is what lets the comparison stop guessing at a noise band.

**Cost.** One run takes about 25 s on lobsters. At `REPEATS = 3` a measurement
takes 4 runs. A full 8-rule Workflow B does 3 measurements per rule, so 96 runs,
or about 40 minutes of benchmark time before contention.

---

## 4. compare_metrics.rb — a measured noise band

**Current.** `NOISE = Float(ENV.fetch("RUBY_TRANSPILE_NOISE", "0.005"))`, one
constant applied to every counter, at lines 27, 98 and 136.

**Change** the band to be per counter:

    band(counter) = max(FLOOR, 2 * max(baseline.spread[counter], candidate.spread[counter]))

- `FLOOR` comes from `RUBY_TRANSPILE_NOISE`, default `0.001`. It stops the band
  collapsing to zero when a counter happens to be identical across runs.
- When either document has no `spread` key, fall back to the current constant and
  add a warning. That keeps an old `baseline.json` readable.

**Add to the output document:**

- `band_pct` inside each entry of `gates`, so a reader sees which band applied.
- `runs` — the repeat count from each side.
- `measurement_warnings` — an array. Push a string when a side has no `spread`,
  and when the two sides used a different `repeats`.

Apply the same per-counter band in the `counter_movers` loop at line 136.

**Also** handle the new `tests: "empty"` value from section 1. The decision chain
at lines 146-163 must reject it, not treat it as a pass.

**Why.** The flat 0.5% band both hides and invents results. It hid the
`remove_intermediate_objects` allocation win at -0.30%, which is 120 times the
measured allocation noise. It would also pass a +0.4% side-exit move as real when
the measured side-exit noise is 0.14%.

---

## 5. verify_rewrite.rb — allow new test files

**Current.** Gate 1 at lines 147-161 rejects any untracked `.rb` except the one
exact path in `ARGV[2]`:

    new_ruby = untracked.select { |p| p.end_with?(".rb") } - [ignore_path]

The ban exists because `patch.diff` comes from `git diff HEAD`, which carries no
untracked file, so a new `.rb` would pass every gate and then vanish.

**Change** `ARGV[2]` to accept a comma-separated list of exact paths and globs.
Match with:

    File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)

The driver passes the benchmark script as it does today. It additionally passes
the test glob, for example `benchmarks/lobsters/spec/**/*_spec.rb`, **only for
the challenge agent**. The rewrite agent passes no glob, so its ban stands
unchanged.

A new `.rb` under `app/` or `lib/` must still fail. The glob is the whole
control, so keep it narrow at the call site.

**Second, separate defect in the same file.** Gate 3 at lines 182-214 is named
`preserve_public_contracts`, but the `Table` visitor never reads `private`,
`public` or `protected`. A rewrite can make a public method private and pass.
Track the visibility section and the `private :sym` and `private def` forms, then
fail when a method public in HEAD is not public in the working copy. Treat this
as a separate commit; it is independent of the rest of this document.

---

## 6. ruby-transpile-rewrite.js — base ref, repeats, cache reset

**Base ref.** See section 1. The worktrees must contain the code under study.
Either set `worktree.baseRef` to `head` in settings, or have the driver assert
after worktree creation that the target directory in the worktree matches the
parent checkout for the files in `paths`, and abort with a clear message when it
does not. Prefer both: the setting fixes it now, the assertion stops it
recurring silently.

**Add two arguments:**

- `measureRepeats`, default 3. Thread it into every `capture_baseline.rb`
  invocation, in the rewrite agent's measure step and in both of the challenge
  agent's remeasure steps.
- `resetCommand`, default none. For lobsters it is `rm -rf tmp/cache`. Run it
  once before the discarded warm-up run, in every harness.

The discarded run alone fixes the cache bias. The reset makes the starting state
explicit and identical on both sides, which matters when a future benchmark
caches something the warm-up does not fully populate.

**Hold the procedure identical on both sides.** The challenge agent must measure
HEAD and candidate with the same `measureRepeats`, the same `resetCommand`, and
in the same session. It already measures in one session; only the repeats and the
reset are new.

---

## 7. ruby-transpile-rewrite.js — specs replace probes

The probe step sits at roughly lines 630-680. Probes found four real defects in
this run and then stayed in `tmp/`, where nothing reads them.

Replace the artifact, keep the technique. The two-tree stdout diff stays as the
challenge agent's private discovery tool, because it finds a divergence quickly
without knowing the expected value. The spec is what ships.

**New procedure for the challenge agent:**

1. Find a divergence with the existing two-tree stdout diff, and list every
   rewritten method with no test coverage.
2. Write an RSpec file under `<target>/spec/transpile/<rule>_spec.rb`, inside the
   challenge agent's own HEAD worktree.
3. Run the suite in the HEAD worktree. The new spec must pass.
4. Copy the spec into the candidate worktree and run the suite there.
5. A failure is a divergence.
6. Emit `tests.diff`:

       git add -N <spec path> && git diff HEAD -- <spec path> > tests.diff

**Step 3 is the load-bearing step.** A spec written against the rewrite passes on
the rewrite and proves nothing. Running it on HEAD first is what pins the
expectation to HEAD and preserves the differential property that the probes had.

**Reachability filter.** Promote a case only when ordinary application code can
produce the receiver. Two examples from this run that should be reported and
dropped, not promoted:

- `stable_object_shapes` built its receiver with
  `Object.instance_method(:freeze).bind(obj).call`, and its own agent reported
  that ActiveRecord cannot produce that object.
- `direct_loops` diverged only after the agent replaced `Vote.where` itself with
  a frozen Array of Structs. Its agent wrote: "Treat the narrowing as a note, not
  as the reason for the verdict." All 5 realistic invocation paths matched.

**Narrow the no-edit rule, do not drop it.** It exists so the adversary cannot
repair the rewrite it judges. The new rule: the challenge agent may create files
under the test path, and may never modify a file listed in `paths`.

**Keep the tripwire step.** It is the only thing that caught fault one. Both
agents that ran it also ran a positive control, which is what made the negative
result trustworthy. Make the positive control part of the procedure, not an
agent's initiative.

**Schema changes.** Replace `probes_written` and `probes_diverged` with
`specs_written` and `specs_failing_on_candidate` at the schema near lines 115-116
and at the reporting sites near lines 809-810 and 940. Update the `overturned`
and `unproven` verdict text near lines 711-718.

`tests.diff` is separate from `patch.diff` on purpose. Workflow C should be able
to take the specs even when it rejects the patch.

---

## 8. SKILL.md updates

In `ruby-transpile-rewrite/SKILL.md`:

- The artifact table gains `tests.diff` and `runs/<rule>/challenge/specs/`, and
  loses `challenge/probes/`.
- The "The Differential Probe" section becomes "The Differential Spec" and
  describes the 4-step run-on-HEAD-first procedure.
- The four-gates table gains the empty-suite rejection.
- The noise-band section replaces the fixed 0.5% claim with the measured band
  formula and the numbers from section 2.
- The Isolation section states the base-ref requirement from section 1.
- The script interface table gains the new `verify_rewrite.rb` glob argument.

In `ruby-transpile-discover/SKILL.md`:

- Document the `REPEATS` argument and the new `runs` and `spread` keys in
  `baseline.json`.
- State that the first run is discarded.
