#!/usr/bin/env bash
# Shared setup of tests/test-evals-runner.sh and tests/test-evals-runner-b.sh (split in v0.24.19 so that neither part is the floor of a CI shard): the api_retry
# transcript line and the ERROR counter that the v0.15.0 AC2.1 section (first half) and the v0.16.0 AC3.4 sections (second half) both use.
# Source it after lib.sh and evals-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
RETRY='{"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"error_status":401,"error":"authentication_failed"}'
RETRY2='{"type":"system","subtype":"api_retry","attempt":2,"max_retries":10,"error_status":401,"error":"authentication_failed"}'
count_err() { printf '%s\n' "$OUT" | grep -c ' ERROR '; }
