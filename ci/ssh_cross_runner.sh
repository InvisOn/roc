#!/usr/bin/env bash
# Run a locally cross-built program on a remote machine over ssh, for
# `run-test-cli --cross-run --cross-runner=ci/ssh_cross_runner.sh`.
#
#   ROC_CROSS_SSH_HOST=user@board ci/ssh_cross_runner.sh PROGRAM [ARGS...]
#
# Copies PROGRAM to /tmp on the host, runs it there with ARGS, passes stdin,
# stdout, stderr and the exit status through, and deletes the copy. ssh hands
# the command line to the remote shell, so every argument is quoted for it
# (the CLI runner passes the expected-output spec, which contains spaces and
# `|`, as one argument). Needs key-based ssh login without prompts.
set -u
host=${ROC_CROSS_SSH_HOST:?set ROC_CROSS_SSH_HOST to the user@host to run on}
program="$1"
shift
remote="/tmp/roc-cross-run.$$.$(basename "$program")"
scp -q "$program" "$host:$remote" || exit 125
ssh -o BatchMode=yes "$host" "$(printf '%q ' "$remote" "$@")"
status=$?
ssh -o BatchMode=yes "$host" rm -f "$remote" </dev/null
exit $status
