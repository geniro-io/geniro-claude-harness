import { flag } from "./flags";

export function readLedger(id: string) {
  if (flag("unified-ledger")) return readUnified(id);
  return readLegacy(id);
}

function readUnified(_id: string) { return { source: "unified" }; }
function readLegacy(_id: string) { return { source: "legacy" }; }
