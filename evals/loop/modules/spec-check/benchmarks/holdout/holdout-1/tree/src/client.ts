import { withRetry } from "./retry";
export const fetchUser = (id: string) => withRetry(() => http(`/users/${id}`));
export const deleteUser = (id: string) => http(`/users/${id}`, "DELETE");
async function http(_p: string, _m = "GET"): Promise<unknown> { return {}; }
