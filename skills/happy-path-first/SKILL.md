---
name: happy-path-first
description: >
  Implement with happy-path-first orchestration, deep modules, type-driven
  invariants, and evidence-driven complexity. Use when implementing a feature,
  writing new code, refactoring toward use-case orchestration, or when the user
  runs /happy-path-first or says "happy path first".
metadata:
  author: Hona
  source: https://gist.github.com/Hona/53142c07c9decb735392f132ace34003
---

Implement the requested change, but optimize the design for the normal user flow. If the happy path is 95% of runtime behavior, it should be approximately 95% of the code readers see.

Start with context:
- inspect the existing code, callsites, data flow, and nearby conventions
- understand the real use case before choosing abstractions
- preserve good repository patterns; do not impose a generic architecture

## Design Vocabulary

Translate the intent into established software design language:

| Desired quality | Established terminology |
| --- | --- |
| Main methods read almost like English | Composed Method, intention-revealing interface, use-case orchestration |
| Orchestrators call well-named services | Application Service, Use Case Interactor, Transaction Script |
| Ugly mechanics stay below a clean interface | Information hiding, deep modules, complexity pulled downward |
| Domain logic does not contain process and network code | Functional Core / Imperative Shell, Ports and Adapters |
| Code is organized around user behavior | Vertical Slice Architecture, use-case-driven architecture, Screaming Architecture |
| Types enforce invariants | Type-driven design, making illegal states unrepresentable |
| Boundary checks produce trusted values | Parse, Don't Validate, smart constructors, refinement types |
| Constructors and assertions enforce contracts | Design by Contract, preconditions, postconditions, invariants |
| Invalid conditions leave before the normal flow | Guard clauses, fail-fast design |
| Imagined requirements do not create code | YAGNI, evolutionary design, avoid speculative generality |
| Reuse follows real repetition | Rule of Three, semantic compression |
| Helpers hide meaningful complexity | Deep rather than shallow modules, locality of behavior |
| State and behavior have one owner | Encapsulation, Tell Don't Ask, Information Expert |

## Patterns Must Pay Rent

Patterns, layers, abstractions, objects, interfaces, and files are costs. Use them only when they produce a concrete readability, maintenance, correctness, testing, or change-isolation gain larger than their cost.

- architecture must be proportional to the real problem
- a pattern name is vocabulary for a design that emerged, not a requirement to manufacture that design
- start with the smallest honest use-case implementation, often a direct Transaction Script or vertical slice
- extract a port, repository, service, value object, or module only when it owns a real invariant, hides real complexity, has multiple real implementations, removes stable duplication, or creates a proven boundary
- judge an abstraction by total system cost: implementation lines, interfaces, files, call hops, configuration, tests, and concepts a reader must learn
- an abstraction that moves ten obvious lines into five files is negative value
- a repository that only renames one database call is a shallow module, not architecture
- do not create `Controller -> Service -> Repository` chains because a diagram, framework, blog post, or pattern says they should exist
- prefer a simple direct method until real domain complexity gives the code a natural cut point

Screaming Architecture does not mean “add architecture layers.” It means the system should reveal its domain and use cases instead of its frameworks. `invoice/pay.ts` can scream the use case more clearly than `controllers/`, `services/`, and `repositories/` full of pass-through methods.

DON'T apply a repository pattern to ten obvious lines:

```ts
class UserController {
  constructor(private service: UserService) {}
  get(id: string) {
    return this.service.get(id)
  }
}

class UserService {
  constructor(private repository: UserRepository) {}
  get(id: string) {
    return this.repository.get(id)
  }
}

class UserRepository {
  get(id: string) {
    return database.selectUser(id)
  }
}
```

DO keep a simple use case simple:

```ts
async function getUser(id: UserID) {
  return database.selectUser(id)
}
```

Add a repository later only when data access becomes a meaningful domain port or hides stable complexity that callers should not know.

## 1. Happy-Path-First Orchestration

Make orchestration read almost like English:

```ts
const version = readBundledVersion()
await installExactVersion(version)
await verifyInstalledVersion(version)
await restartServer()
```

Top-level methods coordinate a use case. They should call well-named domain methods, interfaces, and services. They should not contain parsing, process plumbing, protocol details, state surgery, or long validation branches.

DON'T make the orchestrator own every detail:

```ts
async function update(input: string) {
  if (!input) throw new Error("missing version")
  const child = spawn("wsl", ["bash", "-lc", buildScript(input)])
  const result = await collectOutput(child)
  if (result.code !== 0) throw new Error(result.stderr)
  const installed = parseVersion(await runVersionCommand())
  if (installed !== input) throw new Error("wrong version")
  await killExistingProcess()
  await startProcess()
}
```

DO expose the use case and push mechanics behind deep boundaries:

```ts
async function update(version: Version) {
  await server.stop()
  await cli.install(version)
  await cli.requireVersion(version)
  await server.start()
}
```

## 2. Progressive Disclosure And Guard Clauses

Use progressive disclosure:
- show the happy path first
- move necessary mechanics behind narrow, strongly named boundaries
- isolate ugly platform or integration logic in the lowest-level small method that owns it
- prefer early guards, returns, assertions, and throws so invalid inputs and failed invariants leave immediately
- keep the valid path flat and linear; do not nest it inside defensive branches
- let errors reach the existing user-facing boundary unless recovery is an explicit product requirement

## 3. Deliberate Interfaces And Behavior Ownership

Design interfaces deliberately:
- names must describe domain intent, not implementation mechanics
- dependencies should be explicit and required dependencies should be impossible to omit
- prefer small cohesive interfaces over bags of callbacks, booleans, and optional behavior switches
- put state and its invariants behind one owner
- keep IO in infrastructure and integrations; keep domain decisions out of wrappers
- use classes, services, value objects, or modules when they provide real encapsulation, identity, lifecycle, or polymorphism; do not use OOP as ceremony

## 4. Type-Driven Invariants

Use the type system as design:
- make invalid states unrepresentable where practical
- parse and validate external, persisted, IPC, and network data once at the boundary
- use domain types for meaningful IDs, versions, paths, URLs, states, and results
- return values that answer the caller's actual question
- do not use `any`, loose string protocols, or nullable states when a precise type can express the contract

Make invariants executable:
- enforce invariants through constructors, schemas, value objects, branded types, required parameters, and narrow method signatures
- validate once when data enters the domain; internal methods should receive trusted values instead of repeatedly checking raw data
- use guards and assertions for conditions that must already be true at a callsite
- make required state explicit in parameters instead of reading optional ambient state deep in the flow
- make illegal combinations impossible to construct, not merely documented
- keep invariant ownership close to the type, object, or service that controls the state

DON'T validate raw values and then throw away what the check proved:

```ts
validateVersion(input)
await install(input) // still a raw string
```

DO parse into a trusted domain value once:

```ts
const version = Version.parse(input)
await install(version)
```

DON'T represent mutually exclusive states with nullable fields and booleans:

```ts
type Server = {
  starting: boolean
  url?: string
  error?: string
}
```

DO model the legal states directly:

```ts
type ServerState =
  | { kind: "stopped" }
  | { kind: "starting" }
  | { kind: "ready"; url: ServerUrl }
  | { kind: "failed"; error: ServerError }
```

DON'T pass a loose bag of optional callbacks and behavior flags:

```ts
createServer({ start, stop, read, retry: true, legacy: false })
```

DO require a cohesive interface that answers the caller's real needs:

```ts
createServer({ process: ServerProcess, cli: WslCli })
```

## 5. Evidence Before Complexity

Be aggressively pragmatic:
- prefer one obvious path and one source of truth
- remove duplication, stale compatibility code, speculative safeguards, theoretical race handling, and fallback chains
- do not defend against theoretical or unproven edge cases; wait until a real runtime, log, test reproduction, persisted state, or user report proves the case exists
- when runtime evidence proves an edge case, fix the smallest real failure at the boundary that owns it; do not build a general defense system around one incident
- never justify complexity with “could”, “might”, or “what if” alone; state the observed failure and its likelihood
- do not preserve a bad interface only to avoid changing internal callsites
- do not create a helper for every line; extract only a real concept, reusable operation, or complex boundary
- prefer less code, fewer names, fewer branches, and net-negative diffs when behavior permits

DON'T add lifecycle machinery for an imagined race:

```ts
const attempts = new Map<ID, number>()
// counters, stale ownership checks, retries, cleanup, and fallback paths
// added because two calls might theoretically overlap
```

DO implement the observed flow directly:

```ts
await stopServer(id)
await installCli(version)
await startServer(id)
```

When a real runtime later reports `Text file busy`, use that evidence to add the smallest owned fix: make `stopServer` await process exit before installation. Do not build a general lifecycle framework.

## 6. Proportional Failures And Flat Control Flow

Keep failures proportional:
- handle common operational failures clearly
- fail fast on broken invariants, invalid state, and failed commands
- do not bury the happy path under code for events that should not happen
- an uncommon case gets code only after concrete runtime evidence; if its fix needs substantial machinery, explain the observed failure, frequency, and complexity cost before adding it

DON'T bury the valid path in nested conditionals:

```ts
if (config) {
  if (config.enabled) {
    if (server.ready) {
      return run(config)
    }
  }
}
return undefined
```

DO reject invalid conditions first and leave the valid path flat:

```ts
if (!config) return
if (!config.enabled) return
assert(server.ready)
return run(config)
```

## 7. Deep Modules, Not Helper Shrapnel

DON'T create shallow helpers that force readers to reconstruct one operation:

```ts
prepareUpdate()
doUpdate()
finishUpdate()
```

DO keep tightly related simple code together, or extract one deep operation whose interface hides real complexity:

```ts
await cli.installExactVersion(version)
```

## 8. Encapsulation And State Ownership

DON'T ask for owned state and mutate it elsewhere:

```ts
if (session.status() === "pending") {
  session.messages().push(message)
  session.setStatus("active")
}
```

DO tell the owner the domain operation:

```ts
session.promote(message)
```

## 9. Domain Core And Infrastructure Boundaries

DON'T leak infrastructure into domain decisions:

```ts
function promote(message: Message) {
  spawn("wsl.exe", ...)
  database.insert(message)
}
```

DO keep domain decisions in the core and IO in ports, adapters, or the imperative shell:

```ts
const event = session.promote(message)
await sessionStore.append(event)
```

## 10. Tests At Stable Boundaries

Tests should prove behavior through real boundaries. Do not test one-line helpers, duplicate implementation logic, or build large mock systems for small changes.

DON'T test the implementation sentence by sentence:

```ts
expect(serverIdFor("Debian")).toBe("wsl:Debian")
expect(shouldRestart({ available: false })).toBe(true)
```

DO test the stable use-case boundary and observable order:

```ts
await controller.update("Debian")
expect(events).toEqual(["stop", "install", "verify", "start"])
```

## Completion Standard

Finish the complete change, run focused verification, delete temporary artifacts, and do one final simplification pass. The result should feel boring, obvious, typed, cohesive, and native to the codebase.

The combined style is: **happy-path-first, use-case-oriented design with deep modules, type-driven invariants, boundary isolation, and evidence-driven complexity.**

Adapted from [code-like-luke](https://gist.github.com/Hona/53142c07c9decb735392f132ace34003) by [Hona](https://github.com/Hona).
