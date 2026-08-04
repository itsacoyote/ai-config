# API and Interface Design — Pattern Reference

Concrete patterns referenced from `SKILL.md`. Apply the ones in scope for the
current task — see the "When NOT to Use" section of `SKILL.md` before reaching
for pagination, versioning, or other extension machinery on a narrow interface.

## REST API Patterns

### Resource Design

```
GET    /api/tasks              → List tasks (with query params for filtering)
POST   /api/tasks              → Create a task
GET    /api/tasks/:id          → Get a single task
PATCH  /api/tasks/:id          → Update a task (partial)
DELETE /api/tasks/:id          → Delete a task

GET    /api/tasks/:id/comments → List comments for a task (sub-resource)
POST   /api/tasks/:id/comments → Add a comment to a task
```

### Pagination

Paginate list endpoints that can grow unbounded:

```typescript
// Request
GET /api/tasks?page=1&pageSize=20&sortBy=createdAt&sortOrder=desc

// Response
{
  "data": [...],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "totalItems": 142,
    "totalPages": 8
  }
}
```

### Filtering

Use query parameters for filters:

```
GET /api/tasks?status=in_progress&assignee=user123&createdAfter=2025-01-01
```

### Partial Updates (PATCH)

Accept partial objects — only update what's provided:

```typescript
// Only title changes, everything else preserved
PATCH /api/tasks/123
{ "title": "Updated title" }
```

## TypeScript Interface Patterns

These are the API-design-specific applications of TypeScript's type system. For
the general type-modeling techniques behind them (discriminated unions,
`as const`, branded types, deriving types from values), follow the `typescript-tips`
rule (`.claude/rules/typescript-tips.md`) — don't duplicate that guidance, build on it.

### Use Discriminated Unions for Variants

Model interface states that carry different data per variant so consumers get
type narrowing:

```typescript
type TaskStatus =
  | { type: "pending" }
  | { type: "in_progress"; assignee: string; startedAt: Date }
  | { type: "completed"; completedAt: Date; completedBy: string }
  | { type: "cancelled"; reason: string; cancelledAt: Date };

function getStatusLabel(status: TaskStatus): string {
  switch (status.type) {
    case "pending":
      return "Pending";
    case "in_progress":
      return `In progress (${status.assignee})`;
    case "completed":
      return `Done on ${status.completedAt}`;
    case "cancelled":
      return `Cancelled: ${status.reason}`;
  }
}
```

### Input/Output Separation

Keep the shape the caller provides separate from the shape the system returns.
Output includes server-generated fields the caller never sends:

```typescript
// Input: what the caller provides
interface CreateTaskInput {
  title: string;
  description?: string;
}

// Output: what the system returns (includes server-generated fields)
interface Task {
  id: string;
  title: string;
  description: string | null;
  createdAt: Date;
  updatedAt: Date;
  createdBy: string;
}
```

### Use Branded Types for IDs

Prevents accidentally passing one kind of ID where another is expected:

```typescript
type TaskId = string & { readonly __brand: 'TaskId' };
type UserId = string & { readonly __brand: 'UserId' };

function getTask(id: TaskId): Promise<Task> { ... }
```
