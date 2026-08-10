package api

import "net/http"

func Register(mux *http.ServeMux) {
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/users", usersHandler)
	mux.HandleFunc("/orders", ordersHandler)
}
