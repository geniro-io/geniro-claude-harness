import rollout from "../deploy/rollout.yaml";
import { requestBucket, requestCohort } from "./context";

type FlagSpec = { name: string; enabled: boolean; percentage: number; cohort?: string };

export function flag(name: string): boolean {
  const spec = (rollout.flags as FlagSpec[]).find((f) => f.name === name);
  if (!spec || !spec.enabled) return false;
  if (spec.cohort && spec.cohort !== requestCohort()) return false;
  return requestBucket() < spec.percentage;
}
