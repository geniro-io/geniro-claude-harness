import type { Profile } from "../cache/profile";

// Permissions are resolved per (user, workspace) pair — a user is an admin in
// one workspace and a viewer in another.
export async function loadProfileFromDb(userId: string, workspaceId: string): Promise<Profile> {
  return {
    userId,
    workspaceId,
    displayName: "",
    permissions: [],
  };
}
