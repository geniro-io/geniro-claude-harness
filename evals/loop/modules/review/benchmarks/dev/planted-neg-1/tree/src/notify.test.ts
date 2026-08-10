import { describe, expect, it, vi } from "vitest";
import { sendNotification } from "./notify";

describe("sendNotification", () => {
  it("rejects an empty recipient", () => {
    expect(sendNotification("email", "", "hello")).toBe(false);
  });

  it("rejects an empty body", () => {
    expect(sendNotification("sms", "+15550100", "")).toBe(false);
  });

  it("delivers email for the email channel", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    expect(sendNotification("email", "a@b.co", "hi")).toBe(true);
    expect(log).toHaveBeenCalledWith("email to a@b.co: hi");
    log.mockRestore();
  });

  it("delivers sms for the sms channel", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    expect(sendNotification("sms", "+15550100", "hi")).toBe(true);
    expect(log).toHaveBeenCalledWith("sms to +15550100: hi");
    log.mockRestore();
  });
});
