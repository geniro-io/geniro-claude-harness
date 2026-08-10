import { Worker } from "bullmq";

import { sendEmail, type Notification } from "../notify/email";

export const notifyWorker = new Worker<Notification>("notify", async (job) => {
  await sendEmail(job.data);
});
