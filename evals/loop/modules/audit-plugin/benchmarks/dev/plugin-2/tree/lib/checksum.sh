#!/usr/bin/env bash
# Content hashing for the result cache.

# cache_key — hash stdin into a stable cache key.
cache_key() {
  sha256sum | awk '{print $1}'
}

# file_key — hash one file the same way.
file_key() {
  sha256sum "$1" | awk '{print $1}'
}
