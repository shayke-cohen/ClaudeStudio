.PHONY: build-check sidecar-smoke sidecar-smoke-real sidecar-test feedback feedback-full

# ── Swift build ──────────────────────────────────────────────────────────────

## Compile Odyssey without running tests (~15s). Run after any Swift change.
build-check:
	bash scripts/build-check.sh

# ── Sidecar smoke ─────────────────────────────────────────────────────────────

## Fast smoke: mock provider, no API calls, ~2s. Requires sidecar already running.
sidecar-smoke:
	ODYSSEY_HTTP_PORT=9850 ODYSSEY_WS_TOKEN=$$(ps eww -p $$(lsof -ti:9849 2>/dev/null | head -1) 2>/dev/null | grep -oE 'ODYSSEY_WS_TOKEN=[^ ]+' | cut -d= -f2-) bun run sidecar/test/feedback/quick-smoke.ts

## Full smoke: real Claude call, ~30s. Requires sidecar + ANTHROPIC_API_KEY.
sidecar-smoke-real:
	ODYSSEY_HTTP_PORT=9850 USE_REAL_CLAUDE=1 ODYSSEY_WS_TOKEN=$$(ps eww -p $$(lsof -ti:9849 2>/dev/null | head -1) 2>/dev/null | grep -oE 'ODYSSEY_WS_TOKEN=[^ ]+' | cut -d= -f2-) bun run sidecar/test/feedback/quick-smoke.ts

## Run sidecar API test suite.
sidecar-test:
	cd sidecar && bun run test:api

# ── Feedback loops ────────────────────────────────────────────────────────────

## Fast feedback: build check + mock sidecar smoke (~20s).
feedback: build-check sidecar-smoke
	@echo "✓ Feedback complete"

## Full feedback: build check + real Claude smoke (~50s).
feedback-full: build-check sidecar-smoke-real
	@echo "✓ Full feedback complete"
