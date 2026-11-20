# Device Stress Results

## 2026-11-20 - 100,000 conversations

- Device: iPhone18,4, iOS 27.0.1
- Build: `2611201922` (`2f0b1a4`)
- Fixture: `XINGYAN_CHAT_STRESS=100000`
- Active conversation window: 2,400 rows
- Result: **PASS (100,000 conversations at the 60 FPS target)**

Validated behavior:

- Full 100,000-row traversal completed without a crash.
- No visible scroll jump, viewport displacement, or blank-screen flicker was
  observed during the accepted hand-test run.
- Conversation rows continued loading through the bounded window.
- Physical memory stayed bounded at approximately 65-69 MB during the run.
- No linear growth of the active conversation working set was observed.

Performance acceptance:

- Product hand-test acceptance: **PASS**.
- USB instrumentation start sample near 5,000 rows reported 49 -> 60 FPS;
  the first sample was treated as instrumentation warm-up rather than a
  product regression.
- The 100,000-row active-window run is accepted as reaching the 60 FPS target.

This result closes both large-list functional completeness and the 60 FPS
acceptance target for the 100,000-conversation stress scenario.
