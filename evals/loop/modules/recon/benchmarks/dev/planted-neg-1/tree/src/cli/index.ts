import { Command } from "commander";

import { registerInvoiceCommand } from "./invoice";

const program = new Command();
program.name("ops");
registerInvoiceCommand(program);
program.parse();
