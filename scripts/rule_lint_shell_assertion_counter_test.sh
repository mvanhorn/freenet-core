#!/usr/bin/env bash
# Regression test for the Rule Lint shell-assertion counter in
# .github/workflows/ci.yml -- the grep that decides whether a `fix:` PR whose
# regression test is a shell self-test has any test at all.
#
# WHY THIS FILE EXISTS. That alternation has been wrong three times, and each
# time it was widened only as far as the file in front of whoever was editing.
# The most recent miss was structural rather than a missing spelling: the
# `[[:space:]]` immediately after `(check|ok|pass)` requires the helper's name
# to END there, so EVERY underscore-suffixed helper scored zero --
# `gate_b_arm_case`, `version_ge_case`, `pin_marker`, `check_vs_expected`,
# `check_call_count`, `check_fallback`, `test_restores_persisted_value` and
# more. Measured across every `*_test.sh` in the repo, the original form saw
# roughly three quarters of the assertion call sites; the great majority of the
# misses were in `auto-update-canary_test.sh`, which is written almost entirely
# in that style.
#
# Deliberately no exact figures: they moved three times inside the PR that added
# this file, and a stale number in a justification is the sentence that tells
# the next reader not to re-measure. The computed checks at the bottom of this
# file are where the real numbers live, and they fail naming the files.
#
# Nothing in the repo exercised the regex, so each of those misses was found by
# a human noticing a wrong number rather than by CI. An under-count warns on a
# `fix:` PR that does have a regression test — it used to reject — and the path
# of least resistance for the author is to reshape a good test until the grep
# likes it, or to reach for `test-exempt`.
#
# WHAT IT PINS. Not the regex text -- that would be a copy, and a copy is
# rewritten by the same edit it is supposed to guard (the failure mode #5303
# spent two rounds on). It EXTRACTS the live regex out of ci.yml and runs it
# against call-site shapes taken verbatim from the repo's own test files, in
# both directions. A widening that starts matching plumbing, and a narrowing
# that stops matching an existing convention, both fail here.
#
# It also runs the live rule 5 block — the all-zero branch through the shared
# ERRORS check — against a throwaway repo. A fix: diff that adds no test the
# counter can see must warn once and exit zero; an earlier violation must
# still fail the step.
#
# Run manually: bash scripts/rule_lint_shell_assertion_counter_test.sh
# Also wired into CI (the Fmt job in .github/workflows/ci.yml).

# Every single-quoted string below the fixture header is VERBATIM diff text --
# a line as the counter's grep will see it, `$SRC` and trailing backslashes
# included. Not expanding them is the entire point, so SC2016 ("expressions
# don't expand in single quotes") and SC1003 (a literal trailing backslash read
# as an attempted quote-escape) are both correct observations about code that is
# deliberately literal. Disabled file-wide because the fixtures are the bulk of
# the file; there is no other single-quoted `$` here for the rule to catch.
# shellcheck disable=SC2016,SC1003

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="$SCRIPT_DIR/../.github/workflows/ci.yml"
FAILURES=0

if [[ ! -f "$WF" ]]; then
    echo "FAIL - ci.yml not found at $WF" >&2
    exit 1
fi

# The counter's own line, identified by the two things that make it that line
# rather than any other grep in the file: it pipes into `grep -cE` and its
# alternation mentions PASS.
COUNTER_LINE="$(grep -F "| grep -cE '" "$WF" | grep -F 'PASS' | tail -1)"
FRAG="${COUNTER_LINE#*| grep -cE }"
FRAG="${FRAG% || true)}"

# THE VACUITY GUARD, and it is not boilerplate: the first draft of this file
# extracted the fragment with a `grep -oP` lookbehind that stopped at the
# embedded `'"'"'`, leaving a truncated pattern. An EMPTY pattern makes
# `grep -cE ''` match every line, so all ten negative cases below "passed" while
# reporting 1. A test that cannot fail is exactly what this file exists to stop
# someone else shipping.
if [[ -z "$COUNTER_LINE" || -z "$FRAG" ]]; then
    echo "FAIL - could not find the Rule Lint shell-assertion counter in ci.yml." >&2
    echo "       Looked for a line piping into \`grep -cE '...'\` whose pattern mentions PASS." >&2
    echo "       If the step was reshaped, update this extraction; if it was DELETED, a fix:" >&2
    echo "       PR whose only test is a shell self-test can no longer be recognised at all." >&2
    exit 1
fi
if [[ "$FRAG" != \'*\' ]]; then
    echo "FAIL - the extracted pattern is not a single-quoted shell word: $FRAG" >&2
    echo "       Extraction is out of step with ci.yml; every case below would be unreliable." >&2
    exit 1
fi

# `eval` because FRAG is still shell-quoted, exactly as ci.yml writes it
# (including the `'"'"'` dance for the embedded single quote). Re-quoting it by
# hand here would be the copy this file is built to avoid.
counter_matches() {
    local line="$1" n
    n="$(eval "printf '%s\n' \"\$line\" | grep -cE $FRAG")"
    printf '%s' "$n"
}

expect() {
    # expect <want 0|1> <what the line is> <line, as it appears in a diff>
    local want="$1" desc="$2" line="$3" got
    got="$(counter_matches "$line")"
    if [[ "$got" == "$want" ]]; then
        echo "ok   - $desc"
    else
        echo "FAIL - $desc" >&2
        echo "         line:  $line" >&2
        echo "         wanted the counter to score it $want, it scored $got" >&2
        if [[ "$want" == 1 ]]; then
            echo "       This is a convention the repo's *_test.sh files ALREADY use, so a" >&2
            echo "       fix: PR whose regression test is written this way now scores zero" >&2
            echo "       and the missing-test warning fires. Widen the alternation in" >&2
            echo "       ci.yml rather than reshaping the test." >&2
        else
            echo "       The counter now scores a line that is not an assertion, so a fix:" >&2
            echo "       PR can satisfy the test requirement without adding a test." >&2
        fi
        FAILURES=$((FAILURES + 1))
    fi
}

# --- MUST COUNT: every call-site convention in use across scripts/**/*_test.sh
# Each line is a real one from the file named, with a leading '+' as the diff
# would present it. Add a row here when a new convention appears; that is the
# enumeration the ci.yml comment tells you to re-run.
expect 1 "bare 'check' (most files)" \
    '+check "healthy: check ran, parsed, triggered -> pass" 0 "$HEALTHY"'
expect 1 "bare 'ok' (lifecycle)" \
    '+ok "the canary refuses a node that never checked"'
expect 1 "bare 'pass' (3 files)" \
    '+pass "cross-compile.yml still has the pre-flight failure notification job"'
# THIS file's own convention, and the case that proves the point it makes.
# When this file was first added, EVERY ONE of its `expect` calls scored ZERO --
# the very under-count it exists to prevent, reintroduced by the fix for it,
# inside the same PR, and found by re-measuring rather than by reading. The
# computed check at the bottom of this file is what now catches that shape. Safe as a bare
# name only because nothing in scripts/ drives the TCL `expect(1)`.
expect 1 "bare 'expect' (this file)" \
    '+expect 1 "bare check (most files)" \'
expect 1 "inline echo \"ok   - ...\"" \
    '+    echo "ok   - MARKER_PARSE_FAIL frozen against a rename sweep"'
expect 1 "inline echo 'PASS ...' (release_state_restore_test.sh)" \
    "+echo \"PASS restores the persisted value\""
expect 1 "'*_case' helper: gate_b_arm_case" \
    '+gate_b_arm_case "0.2.126"                   yes   # every release after it'
expect 1 "'*_case' helper: version_ge_case" \
    '+version_ge_case "0.2.123" "0.2.124" no    # strictly below'
expect 1 "'*_case' helper: trigger_case" \
    '+trigger_case "urgent path" "triggering immediate auto-update" yes'
expect 1 "'pin_' helper: pin_marker" \
    '+pin_marker "source pin: disabled marker"        "$SRC"    "$MARKER_DISABLED"'
expect 1 "'pin_' helper: pin_warn_literal, continued on the next line" \
    '+pin_warn_literal "source pin: parse-failure marker (latest-version arm)" \'
expect 1 "'check_' helper: check_vs_expected" \
    '+check_vs_expected "equality: node saw the published tag -> pass" 0 "$SEEN_OK" 0.2.122'
expect 1 "'check_' helper: check_call_count" \
    '+check_call_count "  and it really did re-poll after the failure" jobs 2'
expect 1 "'check_' helper: check_fallback" \
    '+check_fallback "success-fallback + allow empty -> hold (fail closed)" \'
expect 1 "'test_' helper called with arguments" \
    '+test_restores_persisted_value "v0.2.42 regression" "0.3.205" "0.3.206" "0.3.205"'
expect 1 "'test_' helper called with none" \
    '+test_no_persisted_keeps_tentative'

# --- MUST NOT COUNT ---------------------------------------------------------
# A `fix:` PR must not be able to satisfy the test requirement without adding a
# test, so each of these has to score zero.
expect 0 "a helper DEFINITION, not a call" \
    '+check_vs_expected() {'
expect 0 "a '*_case' helper definition" \
    '+gate_b_arm_case() {'
expect 0 "a bare-name helper definition" \
    '+pass() { echo "ok   - $1"; }'
expect 0 "a FAIL branch (deliberate: an error message is not a test)" \
    '+    echo "FAIL - the frozen #5221 signature text changed." >&2'
expect 0 "plumbing: run_driver" \
    '+run_driver "scenario" 3'
expect 0 "plumbing: make_fake_node" \
    '+make_fake_node "$dir" 42'
expect 0 "plumbing: a stub redefinition" \
    '+read_room_state() { READ_CALLS=$((READ_CALLS + 1)); return 0; }'
expect 0 "an ordinary local assignment that happens to start with 'check'" \
    '+local checked=1'
expect 0 "prose in a comment" \
    '+# check that the marker is still frozen'
expect 0 "echo that merely starts with the letters 'ok'" \
    '+    echo "okay, starting the node"'
expect 0 "a bare string added to a table (a KNOWN blind spot, documented in ci.yml)" \
    '+    "$SCRIPT_DIR/release.sh"'

# --- COMPUTED, not asserted in prose ----------------------------------------
# Everything above is a hand-written case. These two are measurements, and they
# are here because the claims they replace were both WRONG in a comment while
# the suite was green.
#
# The rule they come from: a justification that states a COUNT or a GREP RESULT
# is the one kind of comment whose staleness actively suppresses the check that
# would catch it -- it tells the next reader they may stop looking. So compute
# it where it can go red, and let the prose point here.

# 1. EVERY *_test.sh the counter can see must contain at least one line it
#    recognises. A file scoring zero means the counter cannot see that file's
#    convention AT ALL, so a `fix:` PR whose only regression test lives there
#    draws the missing-test warning. This is not hypothetical: when
#    THIS file was added, its 26 bare `expect` calls scored zero -- the miss it
#    exists to prevent, in the file written to prevent it, caught by measuring.
invisible=()
unrun=()
CI_YML="$SCRIPT_DIR/../.github/workflows/ci.yml"
# The Fmt job specifically: it runs on every PR, so a test invoked there is
# genuinely gating. A test invoked from a job that only runs on
# `workflow_dispatch` is not, and scoping here is what makes that distinction.
FMT_JOB=""
if [[ -f "$CI_YML" ]]; then
    # Located by DISPLAY NAME (`name: Fmt`), then read to the next top-level job
    # key. The job KEY is `fmt_check`, which is not guessable from the name --
    # and guessing it wrong is why an earlier version of this found nothing and
    # (correctly) failed rather than passing over an empty body.
    #
    # The display name is what the branch-protection ruleset requires, so it is
    # the stable identifier of "the job that must pass".
    FMT_JOB="$(awk '
        /^  [A-Za-z_.-]+:[[:space:]]*$/ { if (inblock) exit; key = 1; buf = $0; next }
        key && /^    name: Fmt[[:space:]]*$/ { inblock = 1; print buf; print; key = 0; next }
        inblock { print }
        { key = 0 }
    ' "$CI_YML")"
fi

while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    # Same `eval` path as `counter_matches`, so this measures the LIVE pattern
    # rather than a re-quoted copy of it.
    if [[ "$(eval "sed 's/^/+/' \"\$f\" | grep -cE $FRAG")" -eq 0 ]]; then
        invisible+=("$f")
    fi
    # ...AND it must actually be RUN. A test file that no workflow invokes is
    # scored by the counter above and executed by nothing: it looks like
    # coverage in a listing and gates nothing at all.
    #
    # Not hypothetical, and not caught by inspection either time. It was found
    # by hand that `release_state_restore_test.sh` had existed and passed for a
    # long time while ci.yml referenced it only in a COMMENT -- so the v0.2.42
    # regression it was written for had no running gate behind it. A later
    # review then confirmed "no other orphans" by inspection, and demonstrated
    # in the same breath why inspection is not enough: it added a probe test
    # with a real assertion and no `run:` line, and all suites stayed green.
    # This loop is what makes that fail closed.
    #
    # Matched against `run:` LINES specifically, not the whole file, so a
    # mention in a comment -- exactly how the orphan hid -- does not count as
    # being run.
    if [[ -n "$FMT_JOB" ]]; then
        _base="$(basename "$f")"
        # Scanned inside the Fmt JOB only, and over the job's whole body rather
        # than `run:` LINES.
        #
        # Both halves are corrections to a gate that was wrong in BOTH
        # directions:
        #
        #   FALSE-SATISFIED four ways -- a step carrying `if: false`, a step in a
        #   job that only runs on workflow_dispatch, the filename inside an
        #   `echo`, and a path under a directory that does not exist. Scoping to
        #   the Fmt job (which runs on every PR) kills the first two; requiring
        #   a real `bash <path>` invocation kills the third; checking the path
        #   exists kills the fourth.
        #
        #   FALSE-BLOCKING -- a multi-line `run: |` block went RED, because the
        #   invocation is not on the `run:` line itself. That is worse than the
        #   hole: a gate that rejects legitimate usage gets deleted. Scanning
        #   the job body rather than `run:` lines fixes it.
        # Split into STEPS, so the step carrying the invocation can be checked
        # for a conditional. Scanning the job body alone accepted an
        # `if: false` step -- present, never executed, and counted as coverage.
        # Any `if:` disqualifies: a step that is conditional is not guaranteed
        # to run on every PR, which is the whole property being asserted. If a
        # conditional is ever genuinely wanted, that is a deliberate edit here.
        if [[ "$(printf '%s\n' "$FMT_JOB" \
                  | grep -vE '^[[:space:]]*#' \
                  | awk -v needle="$_base" '
                        /^      - (name|uses|run):/ { n++ }
                        { step[n] = step[n] "\n" $0 }
                        END {
                            for (i = 1; i <= n; i++) {
                                # Trailing boundary is load-bearing: without it
                                # `echo "would run bash scripts/x_test.sh"`
                                # matches, because the closing quote sits where
                                # the boundary should be. The explicit echo test
                                # is belt to that braces.
                                #
                                # KNOWN RESIDUAL, recorded rather than papered
                                # over (PR #5443 review). The boundary here is
                                # "any whitespace", so ANY whitespace-delimited
                                # literal sh/bash token immediately before the
                                # path satisfies it -- including a future
                                # `shellcheck -x -s sh scripts/test-install-sh.sh`
                                # in the lint step, where sh is a DIALECT FLAG and
                                # not a shell at all. This closes the case that
                                # exists today (`...-sh.sh <needle>`, where the sh
                                # is preceded by a dot) and no more.
                                # The real fix is to require COMMAND position --
                                # string start, newline, a ;|& separator, or the
                                # YAML run: colon -- instead of any whitespace.
                                # That also wants an optional /path/ prefix so
                                # `/bin/sh x_test.sh` counts, and an optional flag
                                # run so `bash -x x_test.sh` counts: the two
                                # false-BLOCKING forms this currently rejects, and
                                # false-blocking is the worse direction per the
                                # note above. Not done here because it is a fiddly
                                # awk-quoting change that this PR battery could
                                # not validate in one pass. Do it as its own
                                # change. NOTE: no apostrophes in this block --
                                # it lives inside a single-quoted awk program.
                                if (step[i] ~ ("(^|[[:space:]])(bash|sh)[[:space:]]+[^[:space:]]*" needle "([[:space:]]|$)") \
                                    && step[i] !~ ("echo[^;|&$\n]*(^|[[:space:]])(bash|sh)[[:space:]]+[^[:space:]]*" needle) \
                                    && step[i] !~ /\n[[:space:]]+if:/) {
                                    print "RUNS"
                                }
                            }
                        }' \
                  | grep -c RUNS)" -eq 0 ]]; then
            unrun+=("$f")
        fi
    fi
    # Filesystem glob, NOT `git ls-files`, and the difference matters: a
    # contributor adding a test file has not necessarily staged it yet, and that
    # unstaged file is precisely the one whose convention the counter may not
    # know. Mutation-tested -- with `git ls-files` an untracked probe file was
    # invisible to this very check, so the check that exists to find invisible
    # files could not see the newest one.
done < <(find "$SCRIPT_DIR" \( -name '*_test.sh' -o -name 'test-*.sh' \) -type f | sort)

if [[ ! -f "$CI_YML" ]]; then
    echo "FAIL - ci.yml not found at $CI_YML; cannot check that test files are run." >&2
    FAILURES=$((FAILURES + 1))
elif [[ -z "$FMT_JOB" ]]; then
    echo "FAIL - could not locate ci.yml's Fmt job; the run-check examined nothing." >&2
    echo "       This must fail rather than skip: an empty job body would report" >&2
    echo "       every test file as run." >&2
    FAILURES=$((FAILURES + 1))
elif [[ ${#unrun[@]} -eq 0 ]]; then
    echo "ok   - every shell self-test is invoked by 'bash|sh <path>' in ci.yml's Fmt job"
else
    echo "FAIL - these *_test.sh files are never RUN by ci.yml:" >&2
    for f in "${unrun[@]}"; do echo "         $f" >&2; done
    echo "       They are scored by the assertion counter and executed by nothing," >&2
    echo "       so they look like coverage in a listing while gating nothing. Add a" >&2
    echo "       'run: bash scripts/<name>' step to the Fmt job in ci.yml." >&2
    echo "       Checked as a real 'bash <path>' or 'sh <path>' invocation, anchored at a
       word boundary, inside the Fmt JOB, so:" >&2
    echo "       a mention in a comment does not count, nor inside an echo, nor a" >&2
    echo "       step in a job that only runs on workflow_dispatch. A multi-line" >&2
    echo "       'run: |' block DOES count." >&2
    FAILURES=$((FAILURES + 1))
fi

if [[ ${#invisible[@]} -eq 0 ]]; then
    echo "ok   - every tracked *_test.sh contains at least one assertion the counter sees"
else
    echo "FAIL - these *_test.sh files are INVISIBLE to the shell-assertion counter:" >&2
    for f in "${invisible[@]}"; do echo "         $f" >&2; done
    echo "       A fix: PR whose only regression test is in one of them scores zero and" >&2
    echo "       the missing-test warning fires. Either the file uses a convention the" >&2
    echo "       alternation does not know, or it has no assertions at all. Widen the" >&2
    echo "       alternation in ci.yml -- do not reshape the tests to please the grep." >&2
    FAILURES=$((FAILURES + 1))
fi

# 1b. The counter's diff PATHSPECS must reach every shell self-test on disk.
#    Being visible to the alternation is worthless if the diff never shows the
#    file to it in the first place -- that is a SECOND way to be invisible, and
#    it is the one that actually bit us. PR #4958 added ten `check_eq`
#    assertions to `scripts/test-install-sh.sh`, a file ci.yml's Fmt job RUNS,
#    and the `fix:` gate rejected it for having no test: the pathspec was
#    `'**/*_test.sh'` and the file is named `test-*.sh`.
#
#    Check 1 above could never have caught that. It measures the alternation
#    against files it finds with its OWN `find`, so a file the ci.yml pathspec
#    excludes still scores fine here. The two scopes have to be compared to
#    each other, which is what this does.
#
#    COVERAGE IS DECIDED BY GIT, NOT BY A MODEL OF GIT. The first version of
#    this check compared `basename` against `${spec##*/}` -- a hand-written
#    imitation of pathspec matching -- and review demonstrated it wrong three
#    ways, each by mutation: `':(exclude)scripts/test-*.sh'` (the pathspec whose job
#    is to make git SKIP the file) read as coverage OF it, a directory-scoped
#    `'scripts/**/*_test.sh'` read as covering all 13 files where git matches 4,
#    and `'crates/**/*_test.sh'` read as full coverage where git matches none.
#    `git ls-files` is definitionally correct, handles exclude magic and any
#    future pathspec syntax, and cannot drift from what the counter's own
#    `git diff` does.
#
#    `--cached --others --exclude-standard` rather than a plain `ls-files`: a
#    contributor adding a test file has not necessarily staged it, and that
#    unstaged file is exactly the one whose convention the counter may not know
#    -- the same reason the population below comes from `find`. Ignored files
#    stay out.
uncovered=()
pathspec_measured=0
PATHSPEC_HITS="$(grep -cF 'NEW_SHELL_TESTS=$(git diff' "$CI_YML" || true)"
PATHSPEC_LINE="$(grep -F 'NEW_SHELL_TESTS=$(git diff' "$CI_YML" | tail -1 || true)"
if [[ -z "$PATHSPEC_LINE" ]]; then
    echo "FAIL - could not find the NEW_SHELL_TESTS git-diff line in ci.yml." >&2
    echo "       Without it the pathspec scope is unknown and this check examined" >&2
    echo "       nothing; it fails rather than passing vacuously." >&2
    FAILURES=$((FAILURES + 1))
elif [[ "$PATHSPEC_HITS" -ne 1 ]]; then
    # Unbounded `grep -F` would let a COMMENT restating the command union its
    # pathspecs with the live ones, so narrowing the real pathspec stayed green.
    echo "FAIL - found $PATHSPEC_HITS lines matching the NEW_SHELL_TESTS git-diff" >&2
    echo "       command in ci.yml; expected exactly 1. A second occurrence -- even" >&2
    echo "       in a comment -- unions its pathspecs into this measurement and hides" >&2
    echo "       a narrowing of the live one." >&2
    FAILURES=$((FAILURES + 1))
else
    # Everything after the `-- ` separator, as single-quoted words.
    mapfile -t PATHSPECS < <(printf '%s\n' "${PATHSPEC_LINE#*-- }" | grep -oE "'[^']+'" | tr -d "'")
    REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ ${#PATHSPECS[@]} -eq 0 ]]; then
        echo "FAIL - parsed zero pathspecs from ci.yml's NEW_SHELL_TESTS line." >&2
        echo "       An empty list would report every file as uncovered OR as covered" >&2
        echo "       depending on the loop's sense; either way it is not a measurement." >&2
        FAILURES=$((FAILURES + 1))
    elif [[ -z "$REPO_ROOT" ]]; then
        echo "FAIL - not inside a git work tree, so git cannot be asked what the" >&2
        echo "       pathspecs match. This check refuses to guess." >&2
        FAILURES=$((FAILURES + 1))
    else
        covered_set=()
        mapfile -t covered_set < <(
            git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard \
                -- "${PATHSPECS[@]}" 2>/dev/null | sort -u)
        while IFS= read -r f; do
            rel="${f#"$REPO_ROOT"/}"
            covered=0
            for c in ${covered_set[@]+"${covered_set[@]}"}; do
                [[ "$c" == "$rel" ]] && covered=1 && break
            done
            [[ "$covered" -eq 1 ]] || uncovered+=("$rel")
        done < <(find "$SCRIPT_DIR" \( -name '*_test.sh' -o -name 'test-*.sh' \) -type f | sort)
        pathspec_measured=1
    fi
fi

if [[ ${#uncovered[@]} -gt 0 ]]; then
    echo "FAIL - these shell self-tests are outside ci.yml's NEW_SHELL_TESTS pathspecs:" >&2
    for f in "${uncovered[@]}"; do echo "         $f" >&2; done
    echo "       The counter never sees their added lines, so a fix: PR whose only" >&2
    echo "       regression test lives there draws the missing-test warning -- however" >&2
    echo "       many assertions it adds. Add a pathspec to the git diff in ci.yml." >&2
    FAILURES=$((FAILURES + 1))
elif [[ "$pathspec_measured" -eq 1 ]]; then
    # Gated on the flag, not on an empty array: `uncovered` is also empty when
    # the measurement never ran, and an `ok` printed beside its own FAIL asserts
    # exactly the property that was not measured.
    echo "ok   - ci.yml's diff pathspecs reach every shell self-test on disk (asked git)"
fi

# 1c. ...and the count must still be CONSUMED by the gate.
#    Everything above measures how the number is COMPUTED. None of it notices if
#    the number stops being read. Deleting `&& [ "$NEW_SHELL_TESTS" -eq 0 ]`
#    from the gate condition -- the obvious "simplify this" edit -- makes a
#    fix: PR whose only regression test is a shell self-test draw the
#    missing-test warning (PR #4958 was rejected for that) while every other
#    assertion in this file stays green. Found by review, not by the author's
#    own battery.
if grep -qE '\[ "\$NEW_SHELL_TESTS" -eq 0 \]' "$CI_YML" \
   && grep -qE 'if \[ "\$NEW_TESTS" -eq 0 \].*NEW_SHELL_TESTS.*NEW_JS_TESTS' "$CI_YML"; then
    echo "ok   - the fix: gate still consumes NEW_SHELL_TESTS"
else
    echo "FAIL - ci.yml's fix:-needs-a-test condition no longer reads NEW_SHELL_TESTS." >&2
    echo "       The count would be computed and thrown away, so a fix: PR whose only" >&2
    echo "       regression test is a shell self-test draws the missing-test warning --" >&2
    echo "       PR #4958 was rejected for that. Expected all three counters in one" >&2
    echo "       condition: NEW_TESTS, NEW_SHELL_TESTS, NEW_JS_TESTS." >&2
    FAILURES=$((FAILURES + 1))
fi

# 2. The `printf`-style reporter, which ci.yml lists as a known blind spot. That
#    entry was once DELETED on the stated ground that the grep returned nothing;
#    it returns two, in `test-*.sh` files the counter's glob did not used to
#    reach. The sentence was wrong and nothing could tell. The glob now reaches
#    them, and this grep stays scoped to `*_test.sh` deliberately -- see the
#    parenthetical in the failure branch. So: if that convention ever appears in
#    a file the counter DOES scan, the blind spot has stopped being theoretical
#    and this fails.
printf_in_scanned=()
while IFS= read -r hit; do
    printf_in_scanned+=("$hit")
done < <(grep -rnE "printf[[:space:]]+.*['\"](ok|PASS)" \
    "$SCRIPT_DIR"/*_test.sh "$SCRIPT_DIR"/release-agent/*_test.sh 2>/dev/null || true)

if [[ ${#printf_in_scanned[@]} -eq 0 ]]; then
    echo "ok   - no printf-style success reporter in any *_test.sh (the two test-*.sh are excluded on purpose)"
else
    echo "FAIL - a printf-style success reporter now exists in a file the counter SCANS:" >&2
    for hit in "${printf_in_scanned[@]}"; do echo "         $hit" >&2; done
    echo "       ci.yml lists this as a known-but-unreached blind spot. It is now" >&2
    echo "       reached: those assertions score zero. Add a printf pattern to the" >&2
    echo "       alternation and a MUST-COUNT row above, then update ci.yml's list." >&2
    echo "       (scripts/test-install-sh.sh and scripts/test-uninstall-sh.sh are" >&2
    echo "       no longer out of scope -- ci.yml's diff pathspec now includes" >&2
    echo "       'scripts/test-*.sh'. They are excluded from THIS grep on purpose:" >&2
    echo "       only" >&2
    echo "       their 'pass() { printf ... }' DEFINITION is unmatched, while their" >&2
    echo "       'pass \"...\"' and 'check_eq \"...\"' call sites both score. A helper" >&2
    echo "       definition scoring zero is correct, not a blind spot.)" >&2
    FAILURES=$((FAILURES + 1))
fi

# --- Rule 5: no new test is a warning, not a failed step -------------------
# The counter above only sees ADDED lines, so a regression test already on
# the base branch scores zero. Rule 5 used to append an ERROR for that and
# fail the step (#6229), even when that existing test had caught the bug.
# This runs the LIVE block extracted from ci.yml, labels substituted for the
# one GitHub expression bash cannot evaluate, through the shared ERRORS check.
rule5_block="$(awk '
    /TEST_ATTR_RE=/ { capture = 1 }
    capture { print }
    /Rule lint passed/ { exit }
' "$WF")"
if [[ -z "$rule5_block" ]] \
    || ! grep -q 'NEW_SHELL_TESTS' <<< "$rule5_block" \
    || ! grep -q 'pull_request.labels' <<< "$rule5_block" \
    || ! grep -q 'if \[ -n "\$ERRORS" \]' <<< "$rule5_block"; then
    echo "FAIL - could not extract rule 5 through the shared ERRORS check from ci.yml." >&2
    echo "       A fix: PR with no new test would no longer be exercised by this file." >&2
    FAILURES=$((FAILURES + 1))
else
    rule5_root="$(mktemp -d)" || exit 1
    trap 'rm -rf "$rule5_root"' EXIT

    rule5_commit() {
        local dir="$1" msg="$2"
        shift 2
        git -C "$dir" -c user.email=rule-lint@example.com -c user.name='Rule Lint Test' \
            -c commit.gpgsign=false commit -q -m "$msg" "$@"
    }

    rule5_run() {
        local title="$1" labels="$2" errors="$3" repo="$4" base="$5" head="$6"
        local script out rc
        script="$(printf '%s\n' "$rule5_block" | sed "s|\${{ join(github.event.pull_request.labels.\\*\\.name, ',') }}|${labels}|")"
        if grep -q 'pull_request.labels' <<< "$script"; then
            RULE5_OUT="label expression was not substituted"
            RULE5_RC=99
            return
        fi
        # A fresh bash: this file's pipefail must not change the step's own
        # pipeline status, and `exit 1` in the shared check must be the step's.
        out="$(
            PR_TITLE="$title" RULE5_ERRORS="$errors" BASE="$base" HEAD="$head" RULE5_SCRIPT="$script" \
                bash -c 'cd "$1" || exit 99; ERRORS="$RULE5_ERRORS"; eval "$RULE5_SCRIPT"' _ "$repo"
        )"
        rc=$?
        RULE5_OUT="$out"
        RULE5_RC="$rc"
    }

    # rule5_expect <exit> <warning count> <violation still required, or empty> <desc> ...
    rule5_expect() {
        local want_rc="$1" want_warnings="$2" violation="$3" desc="$4"
        shift 4
        local warnings=0 warning_lines="" bad=0
        rule5_run "$@"
        warnings="$(grep -c '::warning::' <<< "$RULE5_OUT" || true)"
        warning_lines="$(grep '::warning::' <<< "$RULE5_OUT" || true)"
        if [[ "$RULE5_RC" -ne "$want_rc" || "$warnings" -ne "$want_warnings" ]]; then
            bad=1
        fi
        # The one warning has to say both things the author can do. A bare
        # `::warning::` would satisfy the count and document nothing.
        if [[ "$want_warnings" -eq 1 ]] \
            && { ! grep -q 'existing regression test' <<< "$warning_lines" \
                || ! grep -q 'add coverage' <<< "$warning_lines"; }; then
            bad=1
        fi
        # Exit zero is only success if the shared check's pass path ran.
        if [[ "$want_rc" -eq 0 ]] && ! grep -q 'Rule lint passed' <<< "$RULE5_OUT"; then
            bad=1
        fi
        # An earlier violation must still be the shared check's failure, not
        # a new message that replaced it.
        if [[ -n "$violation" ]] \
            && { ! grep -qF -- "$violation" <<< "$RULE5_OUT" \
                || ! grep -q '::error::Rule lint failed' <<< "$RULE5_OUT"; }; then
            bad=1
        fi
        if [[ "$bad" -eq 0 ]]; then
            echo "ok   - $desc"
            return
        fi
        echo "FAIL - $desc" >&2
        echo "         wanted exit $want_rc and $want_warnings missing-test warning(s)" >&2
        echo "         got exit $RULE5_RC and $warnings warning(s)" >&2
        if [[ -n "$violation" ]]; then
            echo "         and the original violation still reported: $violation" >&2
        fi
        printf '%s\n' "$RULE5_OUT" | sed 's/^/         output: /' >&2
        FAILURES=$((FAILURES + 1))
    }

    empty="$rule5_root/empty"
    mkdir -p "$empty"
    git -C "$empty" init -q
    rule5_commit "$empty" base --allow-empty
    empty_sha="$(git -C "$empty" rev-parse HEAD)"

    added="$rule5_root/added"
    mkdir -p "$added/scripts"
    git -C "$added" init -q
    printf '%s\n' '# baseline' > "$added/scripts/widget_test.sh"
    git -C "$added" add scripts/widget_test.sh
    rule5_commit "$added" base
    added_base="$(git -C "$added" rev-parse HEAD)"
    printf '%s\n' 'check "covers the bug" 0 0' >> "$added/scripts/widget_test.sh"
    git -C "$added" add scripts/widget_test.sh
    rule5_commit "$added" head
    added_head="$(git -C "$added" rev-parse HEAD)"

    rule5_expect 0 1 "" \
        "fix title, empty diff, empty ERRORS: exit zero and one missing-test warning" \
        "fix: note the existing floor" "" "" "$empty" "$empty_sha" "$empty_sha"
    rule5_expect 1 1 "ERROR: earlier banned pattern" \
        "an earlier violation still fails the step, and the warning is still emitted" \
        "fix: note the existing floor" "" "ERROR: earlier banned pattern" \
        "$empty" "$empty_sha" "$empty_sha"
    rule5_expect 0 1 "" \
        "a scoped fix title triggers the missing-test warning" \
        "fix(rule-lint): note the existing floor" "" "" "$empty" "$empty_sha" "$empty_sha"
    rule5_expect 0 0 "" \
        "an added shell assertion the counter scores suppresses the warning" \
        "fix: note the existing floor" "" "" "$added" "$added_base" "$added_head"
    rule5_expect 0 0 "" \
        "a non-fix title suppresses the warning" \
        "chore: refresh a comment" "" "" "$empty" "$empty_sha" "$empty_sha"
    rule5_expect 0 0 "" \
        "the test-exempt label suppresses the warning" \
        "fix: note the existing floor" "test-exempt" "" "$empty" "$empty_sha" "$empty_sha"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo "All Rule Lint shell-assertion counter assertions passed."
else
    echo "$FAILURES assertion(s) FAILED." >&2
    exit 1
fi
