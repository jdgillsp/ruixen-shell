# Improvement Backlog

<!-- Managed by UseBestJudgment. Edit freely — items are deduplicated by title. -->
<!-- Items promoted from UBJ's Kanban are queued for its iterations; tick one to close it, delete it to withdraw it. -->

## Outstanding

- [ ] **[HIGH]** Add backlog board coverage to notch-ubj-today.sh and cap ubj-today.py request latency  
  _Update bars/widgets/ruixen.notch/ubj-today.py to fetch /api/autonomy/priorities and /api/backlog/board with bounded per-request timeouts (2s) so slow optional endpoints never stall the panel, and add a regression assertion in tests/notch-ubj-today.sh verifying the backlog board summary fields (ready, blocked, held, done, flagged)._  
  **Signals:**
  - b39fb44 added backlog board fetch without dedicated assertion in tests/notch-ubj-today.sh
  *Added: 2026-11-22 · Source: operator · Project: ruixen-shell*
