# Device Stress Results

## 2026-11-20 - 100,000 conversations

- Device: iPhone18,4, iOS 27.0.1
- Build: `2611201922` (`2f0b1a4`)
- Fixture: `XINGYAN_CHAT_STRESS=100000`
- Active conversation window: 2,400 rows
- Result: **PASS (functional completeness)**

Validated behavior:

- Full 100,000-row traversal completed without a crash.
- Conversation rows continued loading through the bounded window.
- Physical memory stayed bounded at approximately 65-69 MB during the run.
- No linear growth of the active conversation working set was observed.

Performance status:

- Start-scroll sample near 5,000 rows: 49 -> 60 FPS.
- The package is not yet marked as a sustained 60 FPS pass.
- Final acceptance still requires a continuous 100,000-row run with minimum
  frame rate, CPU, thermal, and bidirectional-window telemetry recorded.

This result validates large-list functional completeness and bounded working
set. It does not replace the separate 60 FPS acceptance run.
