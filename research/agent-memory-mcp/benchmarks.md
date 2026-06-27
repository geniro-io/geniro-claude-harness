# Benchmarks — caveats and how to run your own

## Do not select on published numbers

Almost all LoCoMo / LongMemEval figures are vendor self-reported, and the
head-to-head claims collapsed under adversarial verification:

| Claim | Verdict |
|---|---|
| Letta 74.0% LoCoMo (filesystem, gpt-4o-mini) > Mem0 68.5% graph variant | confirmed (Mem0's own paper: Mem0g 68.44%) |
| LoCoMo dispute chain: Zep 84% → Mem0 corrected 58.44% → Zep counter 75.14% | confirmed as an open methodology fight |
| Zep 63.8% vs Mem0 49.0% on LongMemEval | **refuted** (0-3, 1-2) — excluded |
| Mem0 2026: 92.5 LoCoMo / 94.4 LongMemEval at ~6,900 tokens | **refuted** (0-3) — excluded |
| Mem0 token efficiency ~26K → ~7K per conversation | confirmed, medium confidence (vendor figure) |

Comparisons are not apples-to-apples: different answer model, judge model, judge
prompt, and question subset. A neutral non-vendor signal worth noting (from an
unverified fetch claim, treat as directional): on **BEAM (ICLR 2026)**,
structured memory beat long-context-alone by 3.5-12.7% accuracy up to 10M-token
windows — i.e. a big context window does not remove the need for memory.

## Run your own (the only number that matters)

Benchmark on your own data and your own answer/judge model, identically across
candidates:

1. **Pick a dataset.** LoCoMo (long multi-session conversational QA) and
   LongMemEval (long-term memory QA) are the standards. For an agent-coding use
   case, also build a small private set of multi-session tasks that mirror how
   Geniro actually accumulates facts.
2. **Fix everything except the memory system.** Same answer model, same judge
   model + prompt, same question subset for every candidate (Mem0, Graphiti,
   and a DIY embeddings + vector-search baseline). The vendor disputes exist
   precisely because these were not held constant.
3. **Measure three axes, not one:** answer accuracy (judge-scored), retrieval
   latency, and tokens injected per turn. A system can win accuracy and lose on
   tokens or latency.
4. **Include the DIY baseline.** Plain embeddings + vector search over the same
   facts is the control — it tells you whether the extra machinery (fact
   extraction, conflict resolution, temporal graph, entity linking) earns its
   keep on your data.

Keep the harness and the per-run captures so results are reproducible across
machines, the same way `../mcp-repo-indexing/scripts/` does for the code-graph
benchmark.
