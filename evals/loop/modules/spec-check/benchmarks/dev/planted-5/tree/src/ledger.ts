import { flag } from "./flags";

export function readLedger(id: string) {
  if (flag("unified-ledger")) return readUnified(id);
  if (flag("legacy-ledger-read")) return readLegacy(id);
  throw new Error("no ledger read path is enabled");
}

function readUnified(_id: string) { return { source: "unified" }; }
function readLegacy(_id: string) { return { source: "legacy" }; }
