# Language-Specific Vulnerability Patterns

Load the relevant section during Step 1 (Scope Resolution) after identifying languages.

---

## JavaScript / TypeScript (Node.js, React, Next.js, Express)

### Critical APIs/calls to flag

```js
eval(); // arbitrary code execution
Function("return ..."); // same as eval
child_process.exec(); // command injection if user input reaches it
fs.readFile; // path traversal if user controls path
fs.writeFile; // path traversal if user controls path
```

### Express.js specific

```js
// Missing helmet (security headers)
const app = express();
// Should have: app.use(helmet())

// Body size limits missing (DoS)
app.use(express.json());
// Should have: app.use(express.json({ limit: '10kb' }))

// CORS misconfiguration
app.use(cors({ origin: "*" })); // too permissive
app.use(cors({ origin: req.headers.origin })); // reflects any origin

// Trust proxy without validation
app.set("trust proxy", true); // only safe behind known proxy
```

### React specific

```jsx
<div dangerouslySetInnerHTML={{ __html: userContent }} />  // XSS
<a href={userUrl}>link</a>  // javascript: URL injection
```

### Next.js specific

```js
// Server Actions without auth
export async function deleteUser(id) {
  // missing: auth check
  await db.users.delete(id);
}

// API Routes missing method validation
export default function handler(req, res) {
  // Should check: if (req.method !== 'POST') return res.status(405)
  doSensitiveAction();
}
```

---

## Ruby on Rails

```ruby
# SQL injection (safe alternatives use placeholders)
User.where("name = '#{params[:name]}'")  # VULNERABLE
User.where("name = ?", params[:name])   # SAFE

# Mass assignment without strong params
@user.update(params[:user])  # should be params.require(:user).permit(...)

# eval / send with user input
eval(params[:code])
send(params[:method])  # arbitrary method call

# Redirect to user-supplied URL (open redirect)
redirect_to params[:url]

# YAML.load (allows arbitrary object creation)
YAML.load(user_input)  # use YAML.safe_load instead
```

