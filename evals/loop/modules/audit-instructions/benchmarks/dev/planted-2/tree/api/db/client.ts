export const client = {
  query(sql: string) {
    return Promise.resolve([sql]);
  },
};
