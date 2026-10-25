# Roc apps that can be tested on arm32

As of 2026-10-20 (reference `9b6c2041d4`).

Two test platforms build for arm32: `test/int` and `test/fx`. Every app on them is
cross-built with the dev backend from x86_64 and run under qemu, on the Pi 5 and on
the Pi 3 by the arm32 checks of every upstream sync. The other test platforms
(`str`, `fx-open`, and the rest of `test/`) have no arm32 runtime objects, so their
apps cannot be built for arm32.

## How to run them

```sh
# every fx app, qemu (arm32musl)
zig build run-test-cli -- --suite platforms --filter test/fx/ --cross-target=arm32musl \
    --cross-opt=dev --cross-run --cross-runner=qemu-arm-static
# the same on a Pi over ssh
ROC_CROSS_SSH_HOST=<user>@<aarch64-device> zig build run-test-cli -- --suite platforms --filter test/fx/ \
    --cross-target=arm32musl --cross-opt=dev --cross-run --cross-runner=ci/ssh_cross_runner.sh --threads 3
# one app: add its name to --filter, e.g. --filter test/fx/hello_world.roc
```

## int platform (`test/int`)

| App | Targets | What it checks |
|---|---|---|
| `test/int/app.roc` | arm32musl, arm32linux (glibc) | Integer operations across widths; its stdout must equal the x64musl build's (54 lines, heap addresses masked) |

## fx platform (`test/fx`): 132 apps, arm32musl

Effectful apps (stdout, stderr, stdin) with expected output, from `io_spec_tests`
in `src/cli/test/fx_test_specs.zig` (descriptions are its own, shortened).
`stdin_while_uaf.roc` runs twice (a short and a 24-character input), so the
runner reports 133 tests.

| App | What it checks |
|---|---|
| `test/fx/var_reassign_in_nested_block_expr.roc` | Nested mutable variable versions remain in scope through operands and compile-time evaluation |
| `test/fx/app.roc` | Basic effectful functions: Stdout.line!, Stderr.line! |
| `test/fx/phantom_capability_parameter.roc` | Repro for: a nominal's phantom parameter survives a call boundary |
| `test/fx/issue_10843_nested_nominal_digest.roc` | Regression test: deeply nested parameterized nominals do not bypass the Monotype digest cache |
| `test/fx/subdir/app.roc` | Relative paths starting with .. |
| `test/fx/stdin_to_stdout.roc` | Stdin to stdout passthrough |
| `test/fx/stdin_echo.roc` | Stdin echo |
| `test/fx/stdin_test.roc` | Stdin with output before and after |
| `test/fx/stdin_simple.roc` | Stdin to stderr |
| `test/fx/spec_constr_single_pass_blocks.roc` | SpecConstr single-pass blocks retain strict effects, recursive captures, shared branch continuations, and early returns |
| `test/fx/parallel_fusion.roc` | Fused numeric iterator continuations execute empty, singleton, and repeated iterations |
| `test/fx/match_str_return.roc` | Match expressions with string returns |
| `test/fx/match_with_wildcard.roc` | Wildcard patterns in match expressions |
| `test/fx/opaque_with_method.roc` | Opaque type with attached method |
| `test/fx/test_issue9034.roc` | Platform-exposed opaque types in type annotations |
| `test/fx/question_mark_operator.roc` | Question mark operator for error propagation |
| `test/fx/numeric_fold.roc` | List.fold with numeric accumulators |
| `test/fx/runtime_dec_to_u8_wrap.roc` | Regression test: wrapping Dec-to-integer conversion in runtime code |
| `test/fx/runtime_dec_to_int_wrap_widths.roc` | Every runtime Dec-to-integer width recovers the whole part and truncates toward zero; all but I128 wrap past the destination range |
| `test/fx/runtime_conversion_exact_widths.roc` | Conversions defined for every source value agree across backends |
| `test/fx/runtime_conversion_wrap_widths.roc` | Wrapping conversions sign-extend a negative source and reduce modulo the destination range |
| `test/fx/runtime_conversion_try_widths.roc` | Fallible conversions return an error when the value does not fit the destination |
| `test/fx/runtime_conversion_trunc_widths.roc` | Float-to-integer conversions discard the fractional part toward zero |
| `test/fx/runtime_float_arith_widths.roc` | Float arithmetic at both widths and signed and float comparisons on runtime values |
| `test/fx/runtime_tail_call_arg_blocks.roc` | Tail calls between functions with argument blocks of different sizes run in constant stack |
| `test/fx/runtime_conversion_to_str_widths.roc` | Every number type renders as text the same way on every backend |
| `test/fx/runtime_i128_div_rem_mod.roc` | Runtime 128-bit division, remainder and modulo agree across backends and keep the operands' full width |
| `test/fx/runtime_i128_to_float.roc` | Runtime 128-bit integer to float conversions agree across backends and keep the operand's full width |
| `test/fx/runtime_abs_diff.roc` | Runtime abs_diff keeps a float difference's fraction and an integer difference wider than the signed operand type |
| `test/fx/runtime_float_abs_negative_zero.roc` | Runtime float abs clears the sign of negative zero on every backend |
| `test/fx/runtime_float_libcalls.roc` | Runtime float remainder and rounding, which compiled code calls the C math library for, agree across backends |
| `test/fx/runtime_zst_list_ownership.roc` | Zero-sized-element lists keep their length through reserve/append/concat and strand no allocation |
| `test/fx/list_for_each.roc` | List.for_each! with effectful callback |
| `test/fx/list_opaque_pattern_match_bug.roc` | Regression test: Pattern matching opaque payload variants retrieved from lists |
| `test/fx/string_pattern_matching.roc` | Pattern matching on string literals |
| `test/fx/hello_world.roc` | Hello world |
| `test/fx/function_wrapper_stdout.roc` | Function wrapper stdout |
| `test/fx/function_wrapper_multiline.roc` | Function wrapper multiline output |
| `test/fx/multiline_stdout.roc` | Multiple stdout lines |
| `test/fx/empty_list_get.roc` | Empty list get returns error |
| `test/fx/str_interp_valid.roc` | String interpolation |
| `test/fx/abi_call_shapes.roc` | Hosted calls whose C signatures are the call shapes a native backend must place exactly (register pairs, stack spill, split records, float back-fill, hidden result pointer) |
| `test/fx/host_interop_padding.roc` | Nominal record declared-order + unnamed padding matches the host C struct layout |
| `test/fx/numeric_lookup_test.roc` | Numeric lookup |
| `test/fx/string_lookup_test.roc` | String lookup |
| `test/fx/dict_pseudo_seed_repro.roc` | Regression test: compiled Dict operations call the hasher builtins |
| `test/fx/issue_10038_top_level_dict.roc` | Regression test: runtime lookup honors a comptime Dict's deterministic seed |
| `test/fx/issue_10038_comptime_dict_transitions.roc` | Regression test: comptime Dict lookup and runtime seed-domain transitions |
| `test/fx/test_direct_string.roc` | Direct string output |
| `test/fx/test_one_call.roc` | Single function call |
| `test/fx/test_with_wrapper.roc` | Function with wrapper |
| `test/fx/inspect_compare_test.roc` | Inspect comparison with and without to_inspect |
| `test/fx/inspect_custom_test.roc` | Custom inspect implementation |
| `test/fx/inspect_nested_test.roc` | Nested struct inspection |
| `test/fx/inspect_no_method_test.roc` | Inspect without to_inspect method |
| `test/fx/inspect_wrong_sig_test.roc` | Inspect ignores a to_inspect that does not return Str |
| `test/fx/inspect_record_test.roc` | Record inspection |
| `test/fx/inspect_dict_set.roc` | Dict and Set inspection uses from_list syntax for direct, empty, polymorphic, and nested values |
| `test/fx/inspect_field_only_repro.roc` | Repro: inspect projected string field |
| `test/fx/inspect_field_concat_repro.roc` | Repro: concat inspected projected string field |
| `test/fx/inspect_field_concat_chain_repro.roc` | Repro: chained concats with inspected projected field |
| `test/fx/cli_map2_help_repro.roc` | Repro: generic record map2 help projection |
| `test/fx/cli_map2_value_repro.roc` | Repro: generic record map2 value projection |
| `test/fx/cli_map2_static_output_repro.roc` | Repro: generic record map2 discarded before static output |
| `test/fx/direct_map2_three_drop_repro.roc` | Repro: dropped three-way direct map2 result before static output |
| `test/fx/direct_map2_three_inner_unused_repro.roc` | Repro: dropped inner direct map2 result before static output |
| `test/fx/direct_map2_three_named_drop_repro.roc` | Repro: named inner and outer direct map2 values dropped before static output |
| `test/fx/direct_map2_three_named_outer_drop_repro.roc` | Repro: named outer direct map2 value dropped before static output |
| `test/fx/control_flow_selected_runtime_representation_repro.roc` | Regression test:  local if binding between iterator call and empty iterator |
| `test/fx/drop_concat_unused_repro.roc` | Repro: dropped concat string before static output |
| `test/fx/drop_record_with_concat_unused_repro.roc` | Repro: dropped record containing concat string before static output |
| `test/fx/run_record_concat_repro.roc` | Repro: proc returns value field from record containing concat string |
| `test/fx/drop_proc_returned_record_repro.roc` | Repro: dropped proc-returned record containing concat string |
| `test/fx/project_inner_help_concat_repro.roc` | Repro: projected inner help concat dropped before static output |
| `test/fx/inspect_open_tag_test.roc` | Str.inspect on tag unions |
| `test/fx/erased_small_first_arg.roc` | Regression test: LLVM erased callable ABI preserves a sub-word first argument |
| `test/fx/packed_list_two_bodies.roc` | Regression test: a packed compile-time list constant restored in two proc bodies must not reuse the first body's GEP instruction |
| `test/fx/unify_scratch_fresh_vars_rank_bug.roc` | Regression test: unify scratch fresh_vars must be cleared between calls |
| `test/fx/recursive_tuple_list.roc` | Regression test: recursive function with List of tuples and append |
| `test/fx/list_map_fallible.roc` | Regression test: List.map with fallible function (U64.from_str) |
| `test/fx/issue_10368_list_map_reuse.roc` | Regression test: optimized List.map reuse preserves a shared parameter-derived input |
| `test/fx/list_append_stdin_uaf.roc` | Regression test: List.append with effectful call on big string (24+ chars) |
| `test/fx/list_first_method.roc` | Regression test: List.first with method syntax |
| `test/fx/list_first_function.roc` | Regression test: List.first with function syntax |
| `test/fx/zst_nested_singleton_shapes.roc` | Nested singleton record/tag ZSTs behave correctly in lists, equality, and pattern matches |
| `test/fx/stdin_while_uaf.roc` | Regression test: Stdin.line! in while loop with 24 char input (heap-allocated string) |
| `test/fx/list_method_get.roc` | Regression test: List.get with method syntax |
| `test/fx/issue8654.roc` | Regression test: Method lookup for nominal types in roc build executables |
| `test/fx/dbg_corrupts_recursive_tag_union.roc` | Regression test: dbg on recursive tag union preserves variant discriminant |
| `test/fx/primitive_encode.roc` | Primitive types have encode methods for static dispatch |
| `test/fx/issue8866.roc` | Regression test: List.append with opaque type containing Str |
| `test/fx/issue8897.roc` | Regression test: Multiple expects with polymorphic function panic |
| `test/fx/issue8897_min.roc` | Regression test: Minimal repro for panic |
| `test/fx/issue8898.roc` | Regression test: Polymorphic function with for loop list literal panic |
| `test/fx/issue_9113_opaque_payload_list_match.roc` | Regression test: Opaque payload in list match works with platform modules |
| `test/fx/static_dispatch_platform_module.roc` | Regression test: Static dispatch on platform-exposed opaque types |
| `test/fx/static_dispatch_effect_bug.roc` | Regression test: Static dispatch on effect methods |
| `test/fx/record_builder_cli_parser.roc` | True applicative record builder: { a: Cli.option(...), b: Cli.flag(...) }.Cli with parameterized Cli(a) type |
| `test/fx/record_builder_test1_repro.roc` | Repro: two-field applicative record builder lowers to the same result as direct map2 |
| `test/fx/record_builder_test2_drop_repro.roc` | Repro: dropped three-field applicative record builder result before static output |
| `test/fx/record_builder_test2_repro.roc` | Repro: three-field applicative record builder preserves Bool field values |
| `test/fx/record_builder_test3_repro.roc` | Repro: four-field applicative record builder preserves field order and values |
| `test/fx/record_builder_test4_repro.roc` | Repro: applicative record builder help text concatenates projected field help exactly once |
| `test/fx/record_builder_test5_repro.roc` | Repro: applicative record builder and direct map2 agree on the same parsed record |
| `test/fx/record_builder_imported_map2_repro.roc` | Regression test: record builder suffix resolves map2 on imported type modules |
| `test/fx/issue9049.roc` | Regression test: Bool.False inspected via opaque type extraction shows correct value |
| `test/fx/hosted_effect_opaque_with_data.roc` | Regression test: Hosted effects on opaque types with data (not just []) |
| `test/fx/file_import_str.roc` | File import as Str: import large file and verify byte count |
| `test/fx/record_field_access.roc` | Regression test: Record field access with alignment-reordered fields (layout order != monotype order) |
| `test/fx/early_return_rc.roc` | Regression test: Early return properly cleans up live refcounted symbols |
| `test/fx/float_comparison.roc` | Regression test: F64 comparisons use float instructions, not integer bit-pattern |
| `test/fx/numeric_abs_runtime.roc` | Regression test: float abs_diff keeps fractions, I128.abs_diff spans the whole range, and abs clears negative zero's sign |
| `test/fx/many_args.roc` | Test: Function with 8 arguments exercises register spilling |
| `test/fx/or_pattern.roc` | Test: OR-pattern (pat1 / pat2 => body) with tag union |
| `test/fx/match_guard_basic.roc` | Match guard: guard passes on wildcard bind |
| `test/fx/match_guard_fallthrough.roc` | Match guard: guard fails, falls to next branch |
| `test/fx/match_guard_tag.roc` | Match guard: guard on tag payload (Some(n) if n > 5) |
| `test/fx/match_guard_multiple.roc` | Match guard: multiple guarded branches, only third matches |
| `test/fx/record_destructure.roc` | Regression test: Record destructuring with alignment-reordered fields |
| `test/fx/cross_module_recursive_nominal.roc` | Cross-module recursive nominal types with pattern matching |
| `test/fx/issue_10203/main.roc` | Regression test: boxed function values in cross-module recursive nominals lower to LIR |
| `test/fx/transitive_import_nominal_equality/main.roc` | Regression test: transitive imports preserve nominal method owner environments for equality |
| `test/fx/issue_11839_untransitive_derived_codec/main.roc` | Regression test: a method calling a derived codec of a nominal absent from its type keeps that nominal's owner reachable from importers |
| `test/fx/test_no_dbg.roc` | Recursive nominal type with List and pattern matching |
| `test/fx/keep_oks.roc` | Regression test: Monomorphize panic when callback always returns Ok but match expects Err tag |
| `test/fx/arc_certifier_large_tree.roc` | Regression test: large refcounted recursive tree passes ARC borrow certification |
| `test/fx/leak_join_with_heap_strs.roc` | Regression test: Str.join_with consuming a unique heap List(Str) frees its element strings (lld-COFF &strDecref misresolution) |
| `test/fx/leak_list_str_ops.roc` | Leak coverage for refcounted-element list ops (concat/drop_at/sublist/replace/swap/append/release_excess_capacity callback paths in dev_wrappers.zig) |
| `test/fx/leak_list_str_drop_nested.roc` | Leak coverage for dropped heap List(Str) and List(List(Str)) (roc_builtins_list_decref_str / _flat_list callback paths) |
| `test/fx/hosted_list_str_ownership.roc` | Regression test for : a hosted function owns a List(Str) argument whose elements the caller still holds, so the caller's retain must cover the element strings the host's release drops |
| `test/fx/tailcc_stack_args.roc` | Regression test for : an AArch64 spill reload right after a call that passes arguments on the stack reads the right slot |
| `test/fx/tailcc_stack_args_tail_group.roc` | Regression test for : calls into a tail group whose members take more arguments than fit in AArch64 registers keep the caller's values intact |

### fx apps not in the arm32 run

These are specs kept outside `io_spec_tests`; Zig tests run them natively with the
interpreter and the dev backend. They build on the fx platform, so they could run
on arm32 too, but nothing runs them there today.

| App | What it checks |
|---|---|
| `test/fx/host_boxed_fn_boundary.roc` | Regression test: Boxed erased callables across the host boundary in both directions |
| `test/fx/loop_break_release.roc` | Regression test: a stream left with break is released at the loop exit |
| `test/fx/branch_entry_release.roc` | Regression test: a value a branch never reads is released at the branch entry |
| `test/fx/le_bytes_append_loop.roc` | A promoted byte-append loop matches a byte-at-a-time construction |
| `test/fx/issue_12196_cold_list_builds.roc` | Regression test: cold-path list literal and List.with_capacity share a builtin |
| `test/fx/take_binding_alias_owned_variant.roc` | Regression test: a taken field passed to an owned variant is released exactly once |
| `test/fx/inline_list_slow_arms.roc` | Inline list fast paths and their builtin slow arms leave the same bytes |

## Not apps, but also run on arm32

- The eval corpus (`src/eval/test/eval_tests.zig`, 2,625 cases): small expressions run by the
  interpreter and the arm32 dev backend under qemu (`-s 64M`).
- The host-effects corpus (106 cases), also under qemu.
