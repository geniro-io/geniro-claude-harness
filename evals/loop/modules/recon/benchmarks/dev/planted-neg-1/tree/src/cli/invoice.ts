import type { Command } from "commander";

import { renderInvoice } from "../billing/invoice";

export function registerInvoiceCommand(program: Command) {
  program
    .command("invoice <id>")
    .description("render one invoice as PDF")
    .action(async (id: string) => {
      process.stdout.write(await renderInvoice(id));
    });
}
