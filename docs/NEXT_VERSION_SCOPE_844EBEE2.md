# Next Version Scope

Baseline: `844ebee2`

This scope is separate from the package built from the same baseline. The
current package remains frozen while these structural changes are developed.

## 1. Sent-Message Conversation Promotion

- Sending a message from chat promotes that conversation in the current
  conversation section immediately.
- Pinned conversations stay ahead of non-pinned conversations.
- The optimistic promotion must survive the server echo, background refresh,
  account switch and app restart.
- A failed send must not reorder the list unless the server later confirms a
  message.
- The native conversation list updates the moved row without reloading the
  entire visible list.

Acceptance:

- Send from any existing conversation and return to the list immediately.
- The target is first within its pinned/non-pinned section.
- No bounce-back after realtime echo or a delayed `chats` response.

## 2. Payment Module Boundary

Split payment into explicit modules:

- `PaymentDomain`: value types, payment intents, state machine, ledger
  contracts and validation rules.
- `PaymentTransport`: authenticated HTTP and callback transport only.
- `PaymentPersistence`: idempotency records, secure local ledger cache and
  device enrollment storage.
- `PaymentCoordinator`: orchestration, retries, cancellation and lifecycle.
- `PaymentUI`: SwiftUI screens that depend on protocols, never concrete
  networking or database types.

The main app only provides navigation, environment configuration and dependency
injection. Payment modules must not import feature pages or global app state.

Acceptance:

- Domain and coordinator test targets compile without SwiftUI or UIKit.
- Intent duplication, timeout, callback replay, cancellation and account switch
  have deterministic tests.
- Existing payment UI and server contracts remain compatible.

## 3. System-Level Music

Split music into:

- `MusicCore`: playback queue, shuffle/repeat, history, resume state and error
  recovery.
- `MusicPlayback`: `AVPlayer`, buffer state, seek, preloading and audio session.
- `MusicSystem`: `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, lock screen,
  Control Center, headphone controls, interruptions and route changes.
- `MusicPersistence`: current item, queue and position restoration.
- `MusicUI`: views that subscribe to immutable state and never own a player.

Acceptance:

- Local playback starts within 150 ms; network playback starts within 800 ms
  under the agreed test network.
- Pause, resume, seek and next track visibly respond within 50 ms.
- Lock screen, Control Center and App state stay synchronized.
- Background continuation, phone-call interruption, headphone removal, AirPlay
  route changes and resume behavior are verified on device.
- Queue and timing screens sustain 60 fps; ProMotion devices use the native
  system refresh rate when available.
- No audio underrun, duplicate playback timer or main-thread state churn.

## 4. Mall Home Extreme Performance

Treat mall home as an independent high-cardinality native feed, not a larger
SwiftUI card stack. The performance work must preserve all existing commerce
flows and must not reduce the available catalog to fake a smooth result.

- Use a native virtualized feed with a bounded active window and a continuous
  prefetch runway.
- Run image decode, downsampling and metadata parsing off the main thread.
- Cancel stale image and page work immediately when the visible window changes.
- Coalesce category, search and filter changes so one gesture cannot generate
  duplicate requests or rebuild the entire feed.
- Keep only visible products plus a small runway in memory; all 9,000 products
  remain reachable without loading or decoding the full catalog.
- Avoid layout invalidation, repeated font measurement, whole-list snapshots and
  main-thread JSON decoding.
- Keep scroll position stable across page consumption, tab changes, background
  refresh and detail-page return.

Acceptance:

- 9,000 home and category products remain fully reachable.
- Cached first frame renders within 300 ms; a warm network first frame renders
  within 800 ms under the agreed test network.
- Continuous scroll holds 60 fps, 1% low frame rate is at least 55 fps, and no
  frame hitch exceeds 50 ms.
- Repeated fast-direction changes, rapid category switches and 2,000-pixel
  flings do not blank the viewport, lock the runway or restore an old offset.
- Image loading never blocks the main thread and memory growth is bounded by the
  active window rather than catalog size.
- Detail return preserves the exact product, row offset and loaded runway.
- Instrumentation records p50/p95/p99 frame time, slow frames, page latency,
  decode latency and memory peak for every performance run.

## Delivery Order

1. Conversation promotion, because it is isolated and can ship independently.
2. Payment boundary, with compatibility tests before any file moves.
3. Music core and system integration, then UI migration.
4. Mall home native feed, image pipeline and scale acceptance.
5. Full device acceptance against the current package to detect regressions.
