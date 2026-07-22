# Active Record Patterns

Durable judgment for modeling and querying. Confirm current method signatures and options in the Rails Guides via `web-search` — this file is about *when* and *why*, not exact syntax.

## Eager loading: `includes` vs `preload` vs `eager_load`

N+1 happens when you load a collection and then touch an association per-row — each access fires another query. Spot it by watching the log for the same query repeating with different IDs (the `bullet` gem flags it automatically).

The three loaders differ in *how* they fetch, and that changes what you can do with the result:

| Method | How it loads | Use when |
|--------|--------------|----------|
| `preload` | Separate query per association (2+ queries, `IN (...)`) | You only need to *read* the association, not filter/sort on it |
| `eager_load` | Single `LEFT OUTER JOIN` | You need to `WHERE`/`ORDER` on the associated table |
| `includes` | Rails decides — preloads, but upgrades to a JOIN if you reference the table in a condition | Default choice; let Rails pick unless you have a reason |

```ruby
# N+1 — one query for posts, then one per post for its author
Post.all.each { |p| p.author.name }

# Fixed — author loaded up front
Post.includes(:author).each { |p| p.author.name }

# Filtering on the association forces a JOIN — use eager_load (or includes + references)
Post.eager_load(:author).where(authors: { verified: true })
```

Pitfall: `includes` + a string `where` referencing the joined table needs `.references(:authors)` or it won't build the JOIN. Nested loads use hashes: `includes(comments: :user)`.

## Scopes vs class methods

Both are chainable. Reach for a **scope** for a simple, named query fragment (`where`/`order`). Reach for a **class method** when there's conditional logic, multiple statements, or you want early returns — they read better and are easier to test. A scope that takes an argument and might return `nil` is a footgun: `nil` breaks chaining, so prefer a class method there.

## Callbacks: use sparingly

Callbacks are fine for *intrinsic* model concerns (normalize an email, generate a slug). They are the wrong place for business logic and side effects (sending mail, calling external services, touching other aggregates): they make models hard to test, fire on every save path including bulk operations, and create hidden ordering dependencies. Push that work into service objects or explicit job enqueues at the call site instead.

Commit-time callbacks (`after_*_commit`) matter when the side effect must not fire until the DB transaction actually commits — e.g. enqueuing a job that will look the record up, or broadcasting a Turbo Stream. Enqueuing in `after_save` can hand a worker an ID that isn't visible yet.

## Query methods worth knowing the trade-offs of

- `pluck` pulls raw columns straight from the DB without instantiating models — much cheaper than `.map(&:attr)` when you just need values. But it ignores already-loaded records, so don't `pluck` inside a loop over a collection you already have in memory.
- `select` limits returned columns, but accessing an unselected attribute on the result raises `MissingAttributeError` — only narrow columns when you control all downstream access.
- `find_each` / `in_batches` page through large tables in chunks so you don't load millions of rows into memory at once. Use them for any backfill or bulk job; plain `.all.each` will OOM at scale.
- `exists?` is cheaper than `.present?`/`.any?` when you only need a yes/no, since it asks the DB for `LIMIT 1` instead of loading rows.
- `counter_cache` avoids a `COUNT` query per parent when you display association counts; the cost is a denormalized column you must trust Rails to maintain.

## Validations vs DB constraints

Model validations give friendly errors but **do not** guarantee integrity — they race under concurrency (two requests both pass a uniqueness check, both insert) and are bypassed by `update_column`, `insert_all`, and raw SQL. For anything that must hold, back the validation with a DB constraint: a unique index for uniqueness, `null: false` for presence, a foreign key for references. Validation for UX, constraint for truth.

## Migrations

- Keep schema changes in migrations; never edit `schema.rb` by hand.
- Separate **schema** changes from **data** backfills. Backfilling inside a schema migration locks you into that model snapshot and can time out on large tables — do data work in a separate migration or a job using `find_each`.
- On large/production tables, adding an index or a `NOT NULL` column can lock the table. Check the current safe-migration approach (e.g. `disable_ddl_transaction!` + `algorithm: :concurrently` for Postgres indexes) via `web-search` before running it.
- Always add indexes for columns used in `WHERE`, `ORDER BY`, or as foreign keys / JOIN targets.

## Concerns

Use a concern to share genuinely common behavior across models (e.g. a `Sluggable` that hooks `before_validation`). Don't use concerns as a dumping ground to shrink a fat model — that just hides the size. If extracted behavior has its own state or collaborators, a service object or plain class is usually clearer than a mixin.

## Performance checklist

- Index frequently-queried columns and FK/JOIN targets.
- `counter_cache` for displayed association counts.
- `select`/`pluck` to avoid hydrating columns you won't use.
- `find_each` for batch processing.
- Database (or materialized) views for expensive recurring aggregations.
