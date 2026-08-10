package api

func Evaluate(key string) (int, any) {
	return 200, map[string]string{"key": key}
}
