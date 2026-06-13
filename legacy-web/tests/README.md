# Tests

Phase 0 of the architectural refactor. The codebase still loads via
`<script>` tags in `index.html`; the test harness mirrors that by reading
each source file and indirect-`eval`ing it in jsdom's global scope.

## Running

```
npm test          # one-shot run
npm run test:watch
```

## Adding a test

1. Decide what scripts the test needs loaded. The default set
   (`CORE_SCRIPTS` in `tests/setup.js`) is data files plus `constants.js`.
2. If you need more, call `loadGameScripts({ include: ['js/foo.js'] })`
   from a `beforeAll` block.
3. Reference loaded symbols via `globalThis.NAME`.

## Why eval?

The existing files use `var X = ...` at module scope and assume
`globalThis === window`. They aren't ES modules. Indirect eval
(`(0, eval)(src)`) attaches `var` declarations to globalThis the same way
a `<script>` tag does.

When Phase 5 converts the codebase to ESM, this harness goes away in
favor of plain `import` statements. Tests written against
`globalThis.X` will need to change to imports at that point.

## What to test here

- **Pure helpers** in `js/combat-engine.js`, `js/state-mutator.js`, etc.
  Anything that takes data in and returns data out without touching the
  DOM or relying on a full combat state.
- **Data integrity** — shapes and required fields of the `data/*.js`
  files. These pin content so a careless data edit fails CI rather than
  crashing the game at runtime.
- **State mutator coverage** (Phase 1+) — once `StateMutator` becomes
  the single writer of state, every mutator should have a test.

Avoid here:
- Anything that needs a real combat to be running. Initialize combat
  through `initCombat` only after Phase 1 has decoupled it from globals.
- DOM rendering. jsdom can do it but the assertions get fragile.
