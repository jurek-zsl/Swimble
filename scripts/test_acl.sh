#!/bin/bash
# Test ACL writes on an isolated Murmur instance; never change the developer's server.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_name="swimble-acl-test-$$"
cleanup() {
  fixture_status=$?
  if [[ "$fixture_status" != 0 ]]; then docker logs --tail 30 "$fixture_name" 2>&1 || true; fi
  docker stop "$fixture_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT
# The credential is only for this disposable localhost-bound test container.
docker run --rm --detach --pull never --name "$fixture_name" \
  --publish 127.0.0.1:64739:64738/tcp --publish 127.0.0.1:64739:64738/udp \
  --env MUMBLE_SUPERUSER_PASSWORD=swimble-local-acl-fixture \
  mumblevoip/mumble-server:latest >/dev/null
fixture_ready=false
for attempt in {1..100}; do
  if docker logs "$fixture_name" 2>&1 | grep -q 'Not registering server as public'; then fixture_ready=true; break; fi
  sleep 0.1
done
if [[ "$fixture_ready" != true ]]; then echo "Murmur fixture did not become ready" >&2; exit 1; fi
cargo test --manifest-path rust-core/Cargo.toml --test murmur_integration test_acl_admin_fixture -- --ignored --nocapture
