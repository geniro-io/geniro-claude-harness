package store

import "context"

type Order struct {
	ID         string
	TotalCents int64
}

// Fetch reads one order. Network errors surface to the caller unchanged.
func (s *OrderStore) Fetch(ctx context.Context, id string) (*Order, error) {
	return s.client.getOrder(ctx, id)
}
