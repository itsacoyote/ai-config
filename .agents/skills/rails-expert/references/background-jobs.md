# Background Jobs with Sidekiq

Durable judgment for deciding *what* to background and *how* to make it safe. Confirm current Sidekiq/Active Job option names and config in the official docs via `web-search`.

## When to background a job

Move work off the request cycle when it is slow, external, or non-essential to the response: sending mail, calling third-party APIs, image/file processing, report generation, bulk updates. The user shouldn't wait, and a flaky external dependency shouldn't fail their request. If the work must finish before you can return a correct response, it is **not** a job — do it inline.

## Pass IDs, not objects

Always enqueue with record IDs and re-`find` inside `perform`. Arguments are serialized to Redis as JSON; a serialized object is a stale snapshot, may be huge, and can fail to round-trip. Re-finding also means the job sees the *current* state, not whatever it was at enqueue time.

```ruby
SendWelcomeJob.perform_later(user.id)   # yes
SendWelcomeJob.perform_later(user)      # no — stale, bloated payload
```

## Idempotency is mandatory

Sidekiq guarantees *at-least-once* delivery: a job can run more than once (retries, crashes mid-run, restarts). Design every job so a second run is harmless. Guard on persisted state, not assumptions.

```ruby
def perform(order_id)
  order = Order.find(order_id)
  return if order.processed?   # cheap guard makes re-runs safe
  order.process!
end
```

For "only one in flight at a time," a uniqueness lock (e.g. `sidekiq-unique-jobs`) prevents duplicate *enqueues* — but it is not a substitute for idempotency, which protects against re-*execution*.

## Retries and failure

- Default behavior retries with exponential backoff. Tune the retry count to the failure mode: transient (network, rate limit) → retry; deterministic (bad data, missing record) → don't waste retries, handle and stop.
- Re-raise to trigger a retry; rescue-and-return when retrying can't help (e.g. `RecordNotFound` — the row is gone).
- Define what happens when retries are exhausted (the dead set / `retries_exhausted` hook): alert, record the failure, or compensate. Silent death is the common production bug.

## Queues and priority

Separate queues by latency sensitivity (`critical` / `default` / `low`) and configure worker weights so a flood of low-priority jobs can't starve urgent ones. Queue names are just strings — the priority only exists if the worker config honors it.

## Keep jobs small

Prefer many small jobs over one giant one: smaller blast radius on failure, better parallelism, easier retries. For bulk work, fan out one child job per item rather than looping over thousands inside a single `perform` (a crash at item 9000 otherwise reruns the first 8999). Batch in groups when per-item overhead matters.

## Scheduled jobs

Recurring work (`sidekiq-cron` or similar) is for periodic maintenance — digests, cleanups, reports. Keep the scheduled job thin: have it enqueue per-item work rather than doing everything inline, so one slow item doesn't block the whole run.

## Testing

Test the unit (`perform_now`) for behavior, and assert *enqueuing* (`have_enqueued_job` with args/queue) separately from execution. Run jobs inline in the test environment so behavior is synchronous and deterministic. Add an explicit test that a second `perform_now` is a no-op to lock in idempotency.

## Monitoring

Watch queue depth and latency, the retry set, and the dead set. A growing backlog or dead set is the early signal of a stuck dependency or a non-idempotent job thrashing. Sidekiq exposes these via `Sidekiq::Queue`, `RetrySet`, `DeadSet` — confirm current API in the docs.
