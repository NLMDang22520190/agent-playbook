# Evidence formats

## Final answer skeleton

```markdown
**Result:** <one sentence>

**Evidence**
- [VERIFIED] Unit tests pass after the change. See the block below.
- [VERIFIED] The overflow comes from `src/money.ts:42` (`amount * 100` on a float).
- [INFERRED] Other currencies are affected too: they share the same `toCents` path (`src/money.ts:40-48`).
- [UNVERIFIED] Production data has no amounts above 2^53 cents (no DB access here).

### Evidence: unit-tests
- command: `pnpm test`
- exit: 0
- ...

**Assumptions:** rounding is half-even (as in `docs/money.md`), not half-up.
**Not done / out of scope:** the same bug in `legacy/` (found, not fixed).
```

## Bug diagnosis

1. Reproduction command and its failing output (evidence block, exit != 0).
2. The root cause at `path:line`, with a short quote.
3. The fix (diff summary).
4. The same reproduction now passing (evidence block, exit 0).
5. A regression test that failed before the fix and passes after.

## Comparing options or recommending

| Criterion | Option A | Option B | Evidence |
|---|---|---|---|
| Supports X | yes | no | A docs URL (v3.2), B issue URL |
| Bundle size | 12 kB | 40 kB | `npx bundlephobia ...` output |

Recommendation + "what would change my mind".

## External facts

- Prefer official docs, the source code, or a reproduction you ran.
- Cite: URL, the version the page describes, and the date you read it if the page is unversioned.
- Short quotes only; paraphrase the rest.
- Secondary sources (blogs, aggregators): label them as such and avoid relying on them alone.

## Anti-patterns (never write these)
- "Should work now." / "Tests should pass." (Run them.)
- "I've verified everything." (Show what, how.)
- "According to the docs..." without a link.
- An evidence block you typed yourself instead of pasting the output.
- `path:line` from memory.
