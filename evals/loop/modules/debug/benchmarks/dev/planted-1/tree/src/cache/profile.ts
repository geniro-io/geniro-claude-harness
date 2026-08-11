import { getJSON, setJSON } from "./redis";

export interface Profile {
  userId: string;
  workspaceId: string;
  displayName: string;
  permissions: string[];
}

// Cache key for a user's resolved profile.
export function profileCacheKey(userId: string): string {
  return `profile:v2:${userId}`;
}

export async function readProfile(userId: string): Promise<Profile | null> {
  return getJSON<Profile>(profileCacheKey(userId));
}

export async function writeProfile(p: Profile): Promise<void> {
  await setJSON(profileCacheKey(p.userId), p);
}
