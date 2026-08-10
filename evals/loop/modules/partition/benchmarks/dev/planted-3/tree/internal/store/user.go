package store

import "context"

type User struct {
	ID    string
	Email string
}

// Fetch reads one user. Network errors surface to the caller unchanged.
func (s *Store) Fetch(ctx context.Context, id string) (*User, error) {
	return s.client.getUser(ctx, id)
}
