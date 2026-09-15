#!/usr/bin/env bash
# Post-build patch: neutralize the Flutter service worker in build/web.
#
# WHY: flutter_service_worker.js caches the whole app, so after every rebuild
# browsers kept serving the OLD bundle until their SW was manually evicted —
# the cause of repeated "my change isn't showing" bugs.
#
# HOW: replaces ONLY flutter_service_worker.js with a self-unregistering
# stub. The bootstrap keeps registering a SW (its code path stays intact),
# but the registered SW immediately unregisters itself and purges every
# cache. Net effect: no persistent caching, no stale bundles, and
# flutter_bootstrap.js is NEVER hand-edited (a hand-edit previously broke
# the minified loader with ReferenceError: e is not defined).
#
# USAGE (after every `flutter build web`, see .freebuff/run.md):
#   bash stylelink/tool/patch_web_no_sw.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SW="$SCRIPT_DIR/../build/web/flutter_service_worker.js"

[ -f "$SW" ] || { echo "ERROR: $SW not found — run flutter build web first." >&2; exit 1; }

cat > "$SW" <<'STUB'
// Self-destructing stub: the Flutter service worker previously cached the
// whole app, serving stale builds after rebuilds. This stub unregisters the
// SW and purges every cache it owns, then skips waiting so the fresh page
// takes over. Static preview serves directly from the network instead.
self.addEventListener('install', (e) => { self.skipWaiting(); });
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.map((n) => caches.delete(n)));
    await self.registration.unregister();
    console.log('[StyleLink] stale service worker removed; caches purged');
  })());
});
STUB

echo "OK: flutter_service_worker.js replaced with self-unregistering stub (bootstrap untouched)."
