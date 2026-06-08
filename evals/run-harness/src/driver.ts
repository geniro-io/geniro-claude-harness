/**
 * Phase-0 gate driver (plan §5, resolution option A).
 *
 * Runs a human-gated, multi-agent geniro skill (/geniro:plan, /geniro:review, …)
 * HEADLESSLY in the MAIN session (so the skill can fan out its own subagents) and
 * auto-answers every `AskUserQuestion` gate via the `approve-default-v1` policy —
 * on the maintainer's Claude SUBSCRIPTION, never the per-token API.
 *
 * Subscription enforcement: ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN are stripped
 * from the child env before the run, and `pathToClaudeCodeExecutable` points at the
 * logged-in CLI, so auth resolves to the OAuth/keychain subscription session.
 *
 * Usage:
 *   tsx src/driver.ts --skill geniro:plan --prompt "add a sum() helper" [opts]
 * Options:
 *   --skill <name>        skill command name (default geniro:plan)
 *   --prompt <text>       args passed to the skill (default "")
 *   --cwd <dir>           target project dir (default: fresh temp git repo)
 *   --plugin-root <path>  geniro plugin dir to load (default: worktree root)
 *   --claude-bin <path>   claude executable (default: resolved from PATH)
 *   --max-turns <n>       top-level turn cap (default 300)
 *   --out <dir>           run-output dir (default runs/<runId>)
 */
import { query } from "@anthropic-ai/claude-agent-sdk";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { approveDefaultV1 } from "./auto-answer.js";
import type { AuqInput } from "./types.js";

// ----- arg parsing -----
function arg(name: string, def = ""): string {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1]! : def;
}
function nowIso(): string {
  return new Date().toISOString();
}

const skill = arg("--skill", "geniro:plan");
const promptArg = arg("--prompt", "");
const maxTurns = Number.parseInt(arg("--max-turns", "300"), 10);
const harnessDir = resolve(import.meta.dirname, "..");
const pluginSrc = resolve(arg("--plugin-root", resolve(harnessDir, "..", "..")));
const pluginRef = arg("--plugin-ref", "HEAD");
const claudeBin = arg("--claude-bin", "") || resolveClaudeBin();

/**
 * Load the plugin under test from a CLEAN, committed-tree copy — never the live dev
 * worktree. Two reasons (both learned in Phase 0):
 *  - A dev worktree is itself a geniro project (carries `.geniro/`, `evals/`, a linked
 *    git worktree) and a *rich codebase*. With an empty/realistic target, the model
 *    will `cd` into CLAUDE_PLUGIN_ROOT and plan/review against the PLUGIN SOURCE
 *    instead of the target — the spec leaks into the worktree and the eval is invalid.
 *  - Pinning a git ref (plan §6 step 2) freezes the prompts/scripts under test.
 * `git archive <ref> | tar -x` yields a pristine tree: no `.git`, no `.geniro`, no
 * untracked `evals/`, no worktree linkage. Pass --plugin-raw to load a dir as-is.
 */
function resolvePluginDir(): string {
  if (process.argv.includes("--plugin-raw")) return pluginSrc;
  const dir = mkdtempSync(join(tmpdir(), "geniro-plugin-"));
  execFileSync(
    "bash",
    ["-lc", 'git -C "$1" archive "$2" | tar -x -C "$3"', "bash", pluginSrc, pluginRef, dir],
    { stdio: ["ignore", "ignore", "inherit"] },
  );
  return dir;
}
const pluginDir = resolvePluginDir();
const runId = `${skill.replace(/[:/]/g, "-")}-${nowIso().replace(/[:.]/g, "-")}`;
const outDir = resolve(arg("--out", join(harnessDir, "runs", runId)));

function resolveClaudeBin(): string {
  try {
    return execFileSync("bash", ["-lc", "command -v claude"], { encoding: "utf8" }).trim();
  } catch {
    return ""; // fall back to the SDK's bundled binary
  }
}

// ----- subscription enforcement (the user's hard constraint) -----
for (const k of ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]) {
  if (process.env[k]) {
    console.error(`[subscription-guard] ${k} is set — stripping it so this run bills against your Claude subscription, not the API.`);
    delete process.env[k];
  }
}
for (const k of ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "CLAUDE_CODE_USE_ANTHROPIC_AWS"]) {
  if (process.env[k]) console.error(`[subscription-guard] WARNING: ${k} is set — run may route to a 3rd-party provider, not your subscription.`);
}
// Allow nesting under a Claude Code session (the eval suite is itself often driven from one).
// `CLAUDECODE=1` is an INTERACTIVE-nesting guard; programmatic subprocess use is safe, so strip it
// from the child env — otherwise the spawned `claude` refuses to start. Mirrors skill-creator's
// run_eval.py (`env = {k:v for k,v in os.environ if k != "CLAUDECODE"}`).
if (process.env.CLAUDECODE) {
  console.error("[driver] stripping CLAUDECODE from the child env so the headless run can nest inside a Claude Code session.");
  delete process.env.CLAUDECODE;
}

// ----- boot self-check (no API spend) -----
// Reaching here proves this module LOADED under tsx (the SDK import at the top resolved, args
// parsed, claude bin located). `run-suite.sh` launches the driver from the worktree root; a bare
// `node --import tsx` resolves the `tsx` specifier against the CWD (no node_modules there) and
// silently ERR_MODULE_NOT_FOUND'd — the first live run died this way and scored a vacuous TIE.
// `--selfcheck` lets a test exercise that exact real invocation for free (run-suite now calls tsx
// by its absolute binary path, so resolution is CWD-independent).
if (process.argv.includes("--selfcheck")) {
  console.error(`[selfcheck] ok — node=${process.version} claude-bin=${claudeBin || "(sdk-bundled)"} sdk-import=ok cwd=${process.cwd()}`);
  process.exit(0);
}

// ----- target project dir (isolated .geniro/state root per trial) -----
let cwd = arg("--cwd", "");
let cwdIsTemp = false;
if (!cwd) {
  cwd = mkdtempSync(join(tmpdir(), "geniro-eval-"));
  cwdIsTemp = true;
  // A minimal git repo so repo-root / branch-slug / review-diff steps work.
  // Deterministic base branch so trials don't vary by the host's init.defaultBranch.
  execFileSync("git", ["init", "-q", "-b", "main"], { cwd });
  execFileSync("git", ["config", "user.email", "eval@geniro.local"], { cwd });
  execFileSync("git", ["config", "user.name", "geniro-eval"], { cwd });
  writeFileSync(join(cwd, "README.md"), "# eval target\n");
  execFileSync("git", ["add", "-A"], { cwd });
  execFileSync("git", ["commit", "-q", "-m", "init"], { cwd });
}
cwd = resolve(cwd);
// Anchor Claude Code's workspace/git-root detection (which walks UP from the host
// process cwd) to the isolated target — not the plugin worktree the driver is run
// from. Without this, the SDK `cwd` option only moves the Bash tool while relative
// Write paths + `git branch` detection resolve against the plugin worktree, leaking
// .geniro/state out of the trial (plan §5 per-trial isolation). See driver findings.
process.chdir(cwd);

mkdirSync(outDir, { recursive: true });
const transcriptPath = join(outDir, "transcript.jsonl");
const gatesPath = join(outDir, "gates.jsonl");
const appendJsonl = (p: string, obj: unknown) => appendFileSync(p, JSON.stringify(obj) + "\n");

const raw = process.argv.includes("--raw");
const prompt = raw ? promptArg : `/${skill} ${promptArg}`.trim();
const meta = {
  run_id: runId,
  started_at: nowIso(),
  skill,
  prompt,
  cwd,
  cwd_is_temp: cwdIsTemp,
  plugin_src: pluginSrc,
  plugin_ref: pluginRef,
  plugin_dir: pluginDir,
  plugin_raw: process.argv.includes("--plugin-raw"),
  claude_bin: claudeBin || "(sdk-bundled)",
  max_turns: maxTurns,
  auq_autoanswer_policy: "approve-default-v1",
  setting_sources: [] as string[],
  node: process.version,
  uses_api_key: Boolean(process.env.ANTHROPIC_API_KEY),
};
writeFileSync(join(outDir, "meta.json"), JSON.stringify(meta, null, 2));

console.error(`[driver] skill=${skill} cwd=${cwd}`);
console.error(`[driver] plugin-dir=${pluginDir} (src=${pluginSrc}@${pluginRef}${process.argv.includes("--plugin-raw") ? " raw" : " archived"})`);
console.error(`[driver] claude-bin=${claudeBin || "(sdk-bundled)"} max-turns=${maxTurns}`);
console.error(`[driver] out=${outDir}`);
console.error(`[driver] prompt=${prompt}`);

// ----- the gate-answering callback -----
const gateLog: unknown[] = [];
const canUseTool = async (toolName: string, input: Record<string, unknown>) => {
  if (toolName !== "AskUserQuestion") {
    return { behavior: "allow" as const, updatedInput: input };
  }
  const auq = input as unknown as AuqInput;
  try {
    const answers = approveDefaultV1(auq);
    const rec = {
      ts: nowIso(),
      gate: (auq.questions ?? []).map((q) => ({
        header: q.header,
        question: q.question,
        options: q.options.map((o) => o.label),
        multiSelect: Boolean(q.multiSelect),
        chosen: answers[q.question],
      })),
    };
    gateLog.push(rec);
    appendJsonl(gatesPath, rec);
    console.error(
      `[gate] answered ${auq.questions.length} q: ` +
        (auq.questions ?? []).map((q) => `${q.header ?? q.question} → ${JSON.stringify(answers[q.question])}`).join(" | "),
    );
    return { behavior: "allow" as const, updatedInput: { questions: auq.questions, answers } };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const rec = { ts: nowIso(), error: msg, questions: auq.questions };
    gateLog.push(rec);
    appendJsonl(gatesPath, rec);
    console.error(`[gate] UNANSWERABLE: ${msg}`);
    return { behavior: "deny" as const, message: `eval-driver(approve-default-v1): ${msg}` };
  }
};

// ----- run -----
const t0 = Date.now();
let result: any = null;
let initSeen = false;
try {
  for await (const msg of query({
    prompt,
    options: {
      cwd,
      plugins: [{ type: "local", path: pluginDir }],
      settingSources: [], // isolated: only the worktree plugin loads, no ambient user/project config
      permissionMode: "default", // NOT bypass — keeps canUseTool firing for the AUQ gates
      maxTurns,
      canUseTool,
      ...(claudeBin ? { pathToClaudeCodeExecutable: claudeBin } : {}),
      stderr: (d: string) => process.stderr.write(d),
    } as any,
  })) {
    appendJsonl(transcriptPath, msg);
    const m = msg as any;
    if (m.type === "system" && m.subtype === "init") {
      initSeen = true;
      console.error(`[init] session=${m.session_id} model=${m.model ?? "?"} tools=${(m.tools ?? []).length} mcp=${(m.mcp_servers ?? []).length}`);
    }
    if (m.type === "result") result = m;
  }
} catch (e) {
  console.error(`[driver] query threw: ${e instanceof Error ? e.stack : e}`);
}

const wallMs = Date.now() - t0;

// ----- collect outputs landing where a grader expects -----
function listGeniroArtifacts(root: string): string[] {
  const found: string[] = [];
  for (const rel of [".geniro/state", ".geniro/planning"]) {
    const p = join(root, rel);
    if (existsSync(p)) {
      try {
        const out = execFileSync("bash", ["-lc", `find ${JSON.stringify(p)} -type f 2>/dev/null | head -50`], { encoding: "utf8" });
        found.push(...out.split("\n").filter(Boolean));
      } catch {
        /* ignore */
      }
    }
  }
  return found;
}
const artifacts = listGeniroArtifacts(cwd);

const summary = {
  ...meta,
  ended_at: nowIso(),
  wall_ms_driver: wallMs,
  init_seen: initSeen,
  completed: Boolean(result) && result.subtype === "success",
  result_subtype: result?.subtype ?? null,
  terminal_reason: result?.terminal_reason ?? null,
  num_turns: result?.num_turns ?? null,
  duration_ms: result?.duration_ms ?? null,
  total_cost_usd: result?.total_cost_usd ?? null,
  usage: result?.usage ?? null,
  model_usage: result?.modelUsage ?? null,
  permission_denials: result?.permission_denials ?? [],
  gates_answered: gateLog.length,
  geniro_artifacts: artifacts,
};
writeFileSync(join(outDir, "result.json"), JSON.stringify(summary, null, 2));

console.error("\n========== PHASE-0 RUN SUMMARY ==========");
console.error(`skill           : ${skill}`);
console.error(`completed        : ${summary.completed}  (subtype=${summary.result_subtype}, terminal=${summary.terminal_reason})`);
console.error(`gates answered   : ${summary.gates_answered}`);
console.error(`turns / wall     : ${summary.num_turns} turns / ${(wallMs / 1000).toFixed(1)}s`);
console.error(`est. cost (usd)  : ${summary.total_cost_usd ?? "n/a"} (subscription billing; estimate only)`);
console.error(`geniro artifacts : ${artifacts.length} file(s)`);
for (const a of artifacts.slice(0, 12)) console.error(`   - ${a.replace(cwd, "<cwd>")}`);
console.error(`outputs          : ${outDir}`);
console.error("=========================================");

process.exit(summary.completed ? 0 : 1);
