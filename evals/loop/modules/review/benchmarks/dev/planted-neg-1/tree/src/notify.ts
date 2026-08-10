type Channel = "email" | "sms";

export function sendNotification(channel: Channel, to: string, body: string): boolean {
  if (!to || !body) {
    return false;
  }
  if (channel === "email") {
    return deliverEmail(to, body);
  }
  return deliverSms(to, body);
}

function deliverEmail(to: string, body: string): boolean {
  console.log(`email to ${to}: ${body}`);
  return true;
}

function deliverSms(to: string, body: string): boolean {
  console.log(`sms to ${to}: ${body}`);
  return true;
}
