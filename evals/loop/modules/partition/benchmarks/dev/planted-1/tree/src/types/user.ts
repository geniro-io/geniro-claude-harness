export type UserRole = "admin" | "member" | "viewer";

export interface User {
  id: string;
  email: string;
  role: UserRole;
  createdAt: Date;
}

export function isPrivileged(u: User): boolean {
  return u.role === "admin";
}
