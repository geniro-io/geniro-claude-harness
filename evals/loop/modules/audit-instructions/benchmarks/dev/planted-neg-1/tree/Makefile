.PHONY: test lint migrate

test:
	go test ./...

lint:
	golangci-lint run

migrate:
	go run ./db/migrate.go up
