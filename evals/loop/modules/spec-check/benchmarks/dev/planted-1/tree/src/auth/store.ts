export const redis = {
  async get(_k: string): Promise<string | null> { return null; },
  async set(_k: string, _v: string, _mode: string, _ttl: number): Promise<void> {},
};
