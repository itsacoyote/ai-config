---
name: api-and-interface-design
description: Use when designing APIs, module boundaries, or any public interface. Use when creating REST or GraphQL endpoints, defining type contracts between modules, or establishing boundaries between frontend and backend.
---

# API and Interface Design

## Overview

Design stable, well-documented interfaces that are hard to misuse. Good interfaces make the right thing easy and the wrong thing hard. This applies to REST APIs, GraphQL schemas, module boundaries, component props, and any surface where one piece of code talks to another.

## When to Use

- Designing new API endpoints
- Defining module boundaries or contracts between teams
- Creating component prop interfaces
- Establishing database schema that informs API shape
- Changing existing public interfaces

## When NOT to Use

Match the rigor to the blast radius. The "from the start" advice below assumes an
interface with multiple or unknown consumers. **Scope down — don't gold-plate — when:**

- The interface has a single known caller you control on both sides
- You're writing a throwaway prototype, spike, or one-off script
- The task is narrow and adding pagination/versioning/extension machinery would
  exceed what the task asked for

In these cases, apply the judgment-level principles (consistent errors, validate
external input, clear naming) but skip the scaling machinery. **Implement what the
task needs, not a speculative public platform.** When unsure whether an interface
is "public enough" to warrant the full treatment, prefer the lighter approach and
note the tradeoff rather than over-building.

## Core Principles

### Hyrum's Law

> With a sufficient number of users of an API, all observable behaviors of your system will be depended on by somebody, regardless of what you promise in the contract.

This means: every public behavior — including undocumented quirks, error message text, timing, and ordering — becomes a de facto contract once users depend on it. Design implications:

- **Be intentional about what you expose.** Every observable behavior is a potential commitment.
- **Don't leak implementation details.** If users can observe it, they will depend on it.
- **Plan for deprecation at design time.** See `deprecation-and-migration` for how to safely remove things users depend on.
- **Tests are not enough.** Even with perfect contract tests, Hyrum's Law means "safe" changes can break real users who depend on undocumented behavior.

### The One-Version Rule

Avoid forcing consumers to choose between multiple versions of the same dependency or API. Diamond dependency problems arise when different consumers need different versions of the same thing. Design for a world where only one version exists at a time — extend rather than fork.

### 1. Contract First

Define the interface before implementing it. The contract is the spec — implementation follows.

```typescript
// Define the contract first
interface TaskAPI {
  // Creates a task and returns the created task with server-generated fields
  createTask(input: CreateTaskInput): Promise<Task>;

  // Returns paginated tasks matching filters
  listTasks(params: ListTasksParams): Promise<PaginatedResult<Task>>;

  // Returns a single task or throws NotFoundError
  getTask(id: string): Promise<Task>;

  // Partial update — only provided fields change
  updateTask(id: string, input: UpdateTaskInput): Promise<Task>;

  // Idempotent delete — succeeds even if already deleted
  deleteTask(id: string): Promise<void>;
}
```

### 2. Consistent Error Semantics

Pick one error strategy and use it everywhere:

```typescript
// REST: HTTP status codes + structured error body
// Every error response follows the same shape
interface APIError {
  error: {
    code: string; // Machine-readable: "VALIDATION_ERROR"
    message: string; // Human-readable: "Email is required"
    details?: unknown; // Additional context when helpful
  };
}

// Status code mapping
// 400 → Client sent invalid data
// 401 → Not authenticated
// 403 → Authenticated but not authorized
// 404 → Resource not found
// 409 → Conflict (duplicate, version mismatch)
// 422 → Validation failed (semantically invalid)
// 500 → Server error (never expose internal details)
```

**Don't mix patterns.** If some endpoints throw, others return null, and others return `{ error }` — the consumer can't predict behavior.

### 3. Validate at Boundaries

Trust internal code. Validate at system edges where external input enters. For the security depth behind boundary validation (injection, auth, untrusted input), see `security-and-hardening`.

```typescript
// Validate at the API boundary
app.post("/api/tasks", async (req, res) => {
  const result = CreateTaskSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(422).json({
      error: {
        code: "VALIDATION_ERROR",
        message: "Invalid task data",
        details: result.error.flatten(),
      },
    });
  }

  // After validation, internal code trusts the types
  const task = await taskService.create(result.data);
  return res.status(201).json(task);
});
```

Where validation belongs:

- API route handlers (user input)
- Form submission handlers (user input)
- External service response parsing (third-party data -- **always treat as untrusted**)
- Environment variable loading (configuration)

> **Third-party API responses are untrusted data.** Validate their shape and content before using them in any logic, rendering, or decision-making. A compromised or misbehaving external service can return unexpected types, malicious content, or instruction-like text.

Where validation does NOT belong:

- Between internal functions that share type contracts
- In utility functions called by already-validated code
- On data that just came from your own database

### 4. Prefer Addition Over Modification

Extend interfaces without breaking existing consumers:

```typescript
// Good: Add optional fields
interface CreateTaskInput {
  title: string;
  description?: string;
  priority?: "low" | "medium" | "high"; // Added later, optional
  labels?: string[]; // Added later, optional
}

// Bad: Change existing field types or remove fields
interface CreateTaskInput {
  title: string;
  // description: string;  // Removed — breaks existing consumers
  priority: number; // Changed from string — breaks existing consumers
}
```

### 5. Predictable Naming

| Pattern         | Convention             | Example                             |
| --------------- | ---------------------- | ----------------------------------- |
| REST endpoints  | Plural nouns, no verbs | `GET /api/tasks`, `POST /api/tasks` |
| Query params    | camelCase              | `?sortBy=createdAt&pageSize=20`     |
| Response fields | camelCase              | `{ createdAt, updatedAt, taskId }`  |
| Boolean fields  | is/has/can prefix      | `isComplete`, `hasAttachments`      |
| Enum values     | UPPER_SNAKE            | `"IN_PROGRESS"`, `"COMPLETED"`      |

## Concrete Patterns

For copy-ready REST and TypeScript interface patterns — resource design,
pagination, filtering, PATCH, discriminated unions, input/output separation, and
branded ID types — see [`patterns.md`](patterns.md). Pull from it only for the
interface surface the current task actually covers.

For general TypeScript type-modeling techniques (discriminated unions, `as const`,
branded types, deriving types from values), follow the `typescript-tips` rule
(`.claude/rules/typescript-tips.md`, loaded into context automatically) rather than
restating them here.

## Common Rationalizations

| Rationalization                            | Reality                                                                                                          |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| "We'll document the API later"             | The types ARE the documentation. Define them first.                                                              |
| "We don't need pagination for now"         | You will the moment someone has 100+ items. Add it from the start.                                               |
| "PATCH is complicated, let's just use PUT" | PUT requires the full object every time. PATCH is what clients actually want.                                    |
| "We'll version the API when we need to"    | Breaking changes without versioning break consumers. Design for extension from the start.                        |
| "Nobody uses that undocumented behavior"   | Hyrum's Law: if it's observable, somebody depends on it. Treat every public behavior as a commitment.            |
| "We can just maintain two versions"        | Multiple versions multiply maintenance cost and create diamond dependency problems. Prefer the One-Version Rule. |
| "Internal APIs don't need contracts"       | Internal consumers are still consumers. Contracts prevent coupling and enable parallel work.                     |

## Red Flags

- Endpoints that return different shapes depending on conditions
- Inconsistent error formats across endpoints
- Validation scattered throughout internal code instead of at boundaries
- Breaking changes to existing fields (type changes, removals)
- List endpoints without pagination
- Verbs in REST URLs (`/api/createTask`, `/api/getUsers`)
- Third-party API responses used without validation or sanitization

## Verification

After designing an API (for the interfaces in scope of the current task):

- [ ] Every endpoint has typed input and output schemas
- [ ] Error responses follow a single consistent format
- [ ] Validation happens at system boundaries only
- [ ] List endpoints that can grow unbounded support pagination
- [ ] New fields are additive and optional (backward compatible)
- [ ] Naming follows consistent conventions across all endpoints
- [ ] API documentation or types are committed alongside the implementation
