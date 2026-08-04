---
name: security-and-hardening
description: Use when handling user input, authentication, data storage, or external integrations — building any feature that accepts untrusted data, manages user sessions, or interacts with third-party services.
---

# Security and Hardening

## Overview

Security-first development practices for web applications. Treat every external input as hostile, every secret as sacred, and every authorization check as mandatory. Security isn't a phase — it's a constraint on every line of code that touches user data, authentication, or external systems.

## When to Use

- Building anything that accepts user input
- Implementing authentication or authorization
- Storing or transmitting sensitive data
- Integrating with external APIs or services
- Adding file uploads, webhooks, or callbacks
- Handling payment or PII data

**When NOT to use:** Purely presentational or internal changes with no untrusted input, secrets, auth, data storage, or external I/O. When in doubt, it applies — under-applying security costs far more than over-applying it.

The code examples are Express/Node/TS; the principles (OWASP prevention, validation at boundaries, hashing, least privilege) are universal — translate them to your stack.

## The Three-Tier Boundary System

### Always Do (No Exceptions)

- **Validate all external input** at the system boundary (API routes, form handlers)
- **Parameterize all database queries** — never concatenate user input into SQL
- **Encode output** to prevent XSS (use framework auto-escaping, don't bypass it)
- **Use HTTPS** for all external communication
- **Hash passwords** with bcrypt/scrypt/argon2 (never store plaintext)
- **Set security headers** (CSP, HSTS, X-Frame-Options, X-Content-Type-Options)
- **Use httpOnly, secure, sameSite cookies** for sessions
- **Run `npm audit`** (or equivalent) before every release

### Ask First (Requires Human Approval)

- Adding new authentication flows or changing auth logic
- Storing new categories of sensitive data (PII, payment info)
- Adding new external service integrations
- Changing CORS configuration
- Adding file upload handlers
- Modifying rate limiting or throttling
- Granting elevated permissions or roles

### Never Do

- **Never commit secrets** to version control (API keys, passwords, tokens)
- **Never log sensitive data** (passwords, tokens, full credit card numbers)
- **Never trust client-side validation** as a security boundary
- **Never disable security headers** for convenience
- **Never use `eval()` or `innerHTML`** with user-provided data
- **Never store sessions in client-accessible storage** (localStorage for auth tokens)
- **Never expose stack traces** or internal error details to users

## OWASP Top 10 Prevention

Prevention map covering all 10 categories (2021 order). The `security-scan` skill is the detective counterpart — see its `references/vuln-categories.md` for detection patterns.

### A01. Broken Access Control

```typescript
// Always check authorization, not just authentication
app.patch("/api/tasks/:id", authenticate, async (req, res) => {
  const task = await taskService.findById(req.params.id);

  // Check that the authenticated user owns this resource
  if (task.ownerId !== req.user.id) {
    return res.status(403).json({
      error: {
        code: "FORBIDDEN",
        message: "Not authorized to modify this task",
      },
    });
  }

  // Proceed with update
  const updated = await taskService.update(req.params.id, req.body);
  return res.json(updated);
});
```

Auth checks on every endpoint, ownership verification on every resource, admin role checked explicitly.

### A02. Cryptographic Failures

```typescript
// Never return sensitive fields in API responses
function sanitizeUser(user: UserRecord): PublicUser {
  const { passwordHash, resetToken, ...publicFields } = user;
  return publicFields;
}

// Use environment variables for secrets
const API_KEY = process.env.STRIPE_API_KEY;
if (!API_KEY) throw new Error("STRIPE_API_KEY not configured");
```

Use HTTPS everywhere, strong hashing (bcrypt/scrypt/argon2) for passwords, never store secrets in code.

### A03. Injection (SQL, NoSQL, OS Command, XSS)

```typescript
// BAD: SQL injection via string concatenation
const query = `SELECT * FROM users WHERE id = '${userId}'`;

// GOOD: Parameterized query
const user = await db.query("SELECT * FROM users WHERE id = $1", [userId]);

// GOOD: ORM with parameterized input
const user = await prisma.user.findUnique({ where: { id: userId } });
```

```typescript
// BAD: Rendering user input as HTML (XSS)
element.innerHTML = userInput;

// GOOD: Use framework auto-escaping (React does this by default)
return <div>{userInput}</div>;

// If you MUST render HTML, sanitize first
import DOMPurify from 'dompurify';
const clean = DOMPurify.sanitize(userInput);
```

Parameterize all queries; validate and allowlist input; use framework auto-escaping for output.

### A04. Insecure Design

Apply threat modeling before implementing sensitive features — identify trust boundaries, data flows, and adversary goals. Use spec-driven development with explicit security requirements. For auth flows, payment handling, or admin features, sketch the attack surface before writing code.

### A05. Security Misconfiguration

```typescript
// Security headers (use helmet for Express)
import helmet from "helmet";
app.use(helmet());

// Content Security Policy
app.use(
  helmet.contentSecurityPolicy({
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"], // Tighten if possible
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'"],
    },
  }),
);

// CORS — restrict to known origins
app.use(
  cors({
    origin: process.env.ALLOWED_ORIGINS?.split(",") || "http://localhost:3000",
    credentials: true,
  }),
);
```

Set security headers, restrict CORS to known origins, use minimal permissions, audit dependencies.

### A06. Vulnerable Components

```bash
# Audit dependencies
npm audit --audit-level=high

# Fix automatically where possible
npm audit fix
```

Run `npm audit` (or equivalent) before every release. Keep dependencies updated. Remove unused packages. See the Triaging npm audit Results section below for triage guidance.

### A07. Identification and Authentication Failures

```typescript
// Password hashing
import { hash, compare } from "bcrypt";

const SALT_ROUNDS = 12;
const hashedPassword = await hash(plaintext, SALT_ROUNDS);
const isValid = await compare(plaintext, hashedPassword);

// Session management
app.use(
  session({
    secret: process.env.SESSION_SECRET, // From environment, not code
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true, // Not accessible via JavaScript
      secure: true, // HTTPS only
      sameSite: "lax", // CSRF protection
      maxAge: 24 * 60 * 60 * 1000, // 24 hours
    },
  }),
);
```

Strong passwords, rate limiting on auth endpoints (≤10 attempts/15 min), session expiration, single-use time-limited reset tokens.

### A08. Software and Data Integrity Failures

Verify the integrity of software updates, CI/CD pipelines, and third-party dependencies. Use signed artifacts and checksums where available. Avoid deserializing untrusted data without schema validation. Audit CI pipelines to ensure build steps cannot be tampered with by injected code.

### A09. Security Logging and Monitoring Failures

Log security-relevant events (authentication, authorization failures, suspicious input patterns). Do not log secrets, passwords, or tokens. Ensure logs are tamper-resistant and monitored. Missing logging means incidents go undetected — it is itself a vulnerability.

### A10. Server-Side Request Forgery (SSRF)

Validate and allowlist URLs before making server-side requests. Restrict outbound requests to known trusted destinations. Block access to internal IP ranges (169.254.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) and cloud metadata endpoints from user-controlled URLs.

## Input Validation Patterns

### Schema Validation at Boundaries

```typescript
import { z } from "zod";

const CreateTaskSchema = z.object({
  title: z.string().min(1).max(200).trim(),
  description: z.string().max(2000).optional(),
  priority: z.enum(["low", "medium", "high"]).default("medium"),
  dueDate: z.string().datetime().optional(),
});

// Validate at the route handler
app.post("/api/tasks", async (req, res) => {
  const result = CreateTaskSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(422).json({
      error: {
        code: "VALIDATION_ERROR",
        message: "Invalid input",
        details: result.error.flatten(),
      },
    });
  }
  // result.data is now typed and validated
  const task = await taskService.create(result.data);
  return res.status(201).json(task);
});
```

### File Upload Safety

```typescript
// Restrict file types and sizes
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_SIZE = 5 * 1024 * 1024; // 5MB

function validateUpload(file: UploadedFile) {
  if (!ALLOWED_TYPES.includes(file.mimetype)) {
    throw new ValidationError("File type not allowed");
  }
  if (file.size > MAX_SIZE) {
    throw new ValidationError("File too large (max 5MB)");
  }
  // Don't trust the file extension — check magic bytes if critical
}
```

## Triaging npm audit Results

Not all audit findings require immediate action. Use this decision tree:

```
npm audit reports a vulnerability
├── Severity: critical or high
│   ├── Is the vulnerable code reachable in your app?
│   │   ├── YES --> Fix immediately (update, patch, or replace the dependency)
│   │   └── NO (dev-only dep, unused code path) --> Fix soon, but not a blocker
│   └── Is a fix available?
│       ├── YES --> Update to the patched version
│       └── NO --> Check for workarounds, consider replacing the dependency, or add to allowlist with a review date
├── Severity: moderate
│   ├── Reachable in production? --> Fix in the next release cycle
│   └── Dev-only? --> Fix when convenient, track in backlog
└── Severity: low
    └── Track and fix during regular dependency updates
```

**Key questions:**

- Is the vulnerable function actually called in your code path?
- Is the dependency a runtime dependency or dev-only?
- Is the vulnerability exploitable given your deployment context (e.g., a server-side vulnerability in a client-only app)?

When you defer a fix, document the reason and set a review date.

## Rate Limiting

```typescript
import rateLimit from "express-rate-limit";

// General API rate limit
app.use(
  "/api/",
  rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // 100 requests per window
    standardHeaders: true,
    legacyHeaders: false,
  }),
);

// Stricter limit for auth endpoints
app.use(
  "/api/auth/",
  rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10, // 10 attempts per 15 minutes
  }),
);
```

## Secrets Management

```
.env files:
  ├── .env.example  → Committed (template with placeholder values)
  ├── .env          → NOT committed (contains real secrets)
  └── .env.local    → NOT committed (local overrides)

.gitignore must include:
  .env
  .env.local
  .env.*.local
  *.pem
  *.key
```

**Always check before committing:**

```bash
# Check for accidentally staged secrets
git diff --cached | grep -i "password\|secret\|api_key\|token"
```

## Security Review Quick Reference

For a fast pre-commit pass, use `.claude/references/security-checklist.md` — it has copy-paste security headers, CORS configuration, pre-commit grep checks, and dependency audit commands. That file is a quick-ref that links back here for the authoritative prevention guidance.

## See Also

- `.claude/references/security-checklist.md` — actionable quick-ref: pre-commit checks, copy-paste headers/CORS/error snippets
- `api-and-interface-design` — where validation belongs at interface boundaries
- `browser-testing-with-devtools` — verify security headers and responses against the running app
- `security-scan` — audit existing or changed code for vulnerabilities (the detective counterpart to this preventive skill; its `references/vuln-categories.md` has detection patterns for every OWASP category)

## Common Rationalizations

| Rationalization                                     | Reality                                                                         |
| --------------------------------------------------- | ------------------------------------------------------------------------------- |
| "This is an internal tool, security doesn't matter" | Internal tools get compromised. Attackers target the weakest link.              |
| "We'll add security later"                          | Security retrofitting is 10x harder than building it in. Add it now.            |
| "No one would try to exploit this"                  | Automated scanners will find it. Security by obscurity is not security.         |
| "The framework handles security"                    | Frameworks provide tools, not guarantees. You still need to use them correctly. |
| "It's just a prototype"                             | Prototypes become production. Security habits from day one.                     |

## Red Flags

- User input passed directly to database queries, shell commands, or HTML rendering
- Secrets in source code or commit history
- API endpoints without authentication or authorization checks
- Missing CORS configuration or wildcard (`*`) origins
- No rate limiting on authentication endpoints
- Stack traces or internal errors exposed to users
- Dependencies with known critical vulnerabilities

## Verification

After implementing security-relevant code:

- [ ] `npm audit` shows no critical or high vulnerabilities
- [ ] No secrets in source code or git history
- [ ] All user input validated at system boundaries
- [ ] Authentication and authorization checked on every protected endpoint
- [ ] Security headers present in response (check with browser DevTools)
- [ ] Error responses don't expose internal details
- [ ] Rate limiting active on auth endpoints
