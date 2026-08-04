---
name: rails-expert
description: Use when building Rails 7+ web applications — Hotwire/Turbo Frames and Streams for partial page updates, Action Cable WebSockets, Sidekiq background jobs, or Active Record query optimization with includes/eager_load. Use for real-time features, background job processing, RESTful API mode, and RSpec test suites in Rails projects.
---

# Rails Expert

Senior Rails specialist with deep expertise in Rails 7+, Hotwire, and production-grade application architecture.

## When to Use

- Building Rails 7+ web applications
- Optimizing Active Record queries — N+1 prevention, `includes`/`eager_load`, indexes
- Adding Hotwire — Turbo Frames, Turbo Streams, Stimulus controllers
- Real-time features with Action Cable (WebSockets)
- Background jobs with Sidekiq
- Building API-only Rails endpoints
- Writing RSpec model, request, and system specs

## Core Workflow

1. **Analyze requirements** — Identify models, routes, real-time needs, background jobs
2. **Scaffold resources** — `rails generate model User name:string email:string`, `rails generate controller Users`
3. **Run migrations** — `rails db:migrate` and verify schema with `rails db:schema:dump`
   - If migration fails: inspect `db/schema.rb` for conflicts, rollback with `rails db:rollback`, fix and retry
4. **Implement** — Write controllers, models, add Hotwire (see Reference Guide below)
5. **Validate** — `bundle exec rspec` must pass; `bundle exec rubocop` for style
   - If specs fail: check error output, fix failing examples, re-run with `--format documentation` for detail
   - If N+1 queries surface during review: add `includes`/`eager_load` (see Code Examples) and re-run specs
6. **Optimize** — Audit for N+1 queries, add missing indexes, add caching

## Reference Guide

Load detailed guidance based on context:

| Topic | Reference | Load When |
|-------|-----------|-----------|
| Hotwire/Turbo | `references/hotwire-turbo.md` | Turbo Frames, Streams, Stimulus controllers |
| Active Record | `references/active-record.md` | Models, associations, queries, performance |
| Background Jobs | `references/background-jobs.md` | Sidekiq, job design, queues, error handling |

## Code Examples

### N+1 Prevention with includes/eager_load

```ruby
# BAD — triggers N+1
posts = Post.all
posts.each { |post| puts post.author.name }

# GOOD — eager load association
posts = Post.includes(:author).all
posts.each { |post| puts post.author.name }

# GOOD — eager_load forces a JOIN (useful when filtering on association)
posts = Post.eager_load(:author).where(authors: { verified: true })
```

### Turbo Frame Setup (partial page update)

```erb
<%# app/views/posts/index.html.erb %>
<%= turbo_frame_tag "posts" do %>
  <%= render @posts %>
  <%= link_to "Load More", posts_path(page: @next_page) %>
<% end %>

<%# app/views/posts/_post.html.erb %>
<%= turbo_frame_tag dom_id(post) do %>
  <h2><%= post.title %></h2>
  <%= link_to "Edit", edit_post_path(post) %>
<% end %>
```

```ruby
# app/controllers/posts_controller.rb
def index
  @posts = Post.includes(:author).page(params[:page])
  @next_page = @posts.next_page
end
```

### Sidekiq Worker Template

```ruby
# app/jobs/send_welcome_email_job.rb
class SendWelcomeEmailJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 3, dead: false

  def perform(user_id)
    user = User.find(user_id)
    UserMailer.welcome(user).deliver_now
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("SendWelcomeEmailJob: user #{user_id} not found — #{e.message}")
    # Do not re-raise; record is gone, no point retrying
  end
end

# Enqueue from controller or model callback
SendWelcomeEmailJob.perform_later(user.id)
```

### Idempotent job shape

```ruby
def perform(order_id)
  order = Order.find(order_id)
  return if order.processed?   # at-least-once delivery → re-runs must be safe
  order.process!
end
```

Keep controllers thin: whitelist input with strong parameters, re-render `:new`/`:edit` with `status: :unprocessable_entity` on validation failure, and push business logic into service objects. Confirm current controller/strong-params syntax in the Rails guides via `web-search`.

## Constraints

### MUST DO
- Prevent N+1 queries with `includes`/`eager_load` on every collection query involving associations
- Write comprehensive specs targeting >95% coverage
- Use service objects for complex business logic; keep controllers thin
- Add database indexes for every column used in `WHERE`, `ORDER BY`, or `JOIN`
- Offload slow operations to Sidekiq — never run them synchronously in a request cycle

### MUST NOT DO
- Skip migrations for schema changes
- Use raw SQL without sanitization (`sanitize_sql` or parameterized queries only)
- Expose internal IDs in URLs without consideration

## Output Order

When implementing Rails features, provide: migration file (if schema changes are needed) → model with associations and validations → controller with RESTful actions and strong parameters → view files or Hotwire setup → spec files for models and requests → a brief note on the architectural decisions.

## Related Skills

- **`writing-tests`** — general test design and what to cover; this skill shows the RSpec specifics.
- **`security-and-hardening`** — auth, input validation, and session hardening; this skill shows the Rails strong-params / token-auth implementation.
- **`api-and-interface-design`** — API contract design; this skill shows the Rails API-mode implementation.
