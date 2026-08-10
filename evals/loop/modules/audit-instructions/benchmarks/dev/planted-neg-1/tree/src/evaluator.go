package flags

import "strings"

const cacheTTLSeconds = 30

func normalizeKey(key string) string {
	return strings.ToLower(key)
}
