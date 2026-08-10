package store

// There is no shared retry/backoff utility in this module today; every call
// site surfaces transport errors directly to its caller.

type Store struct{ client *apiClient }

type OrderStore struct{ client *apiClient }

type apiClient struct{}
