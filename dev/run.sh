#!/bin/bash
# VENOM Development Environment
# Usage: ./run.sh [headless|gpu]

set -e

cd "$(dirname "$0")"

MODE="${1:-gpu}"

case "$MODE" in
    headless)
        echo "Starting headless development environment..."
        docker compose up -d venom-headless
        docker compose exec venom-headless bash
        ;;
    gpu|*)
        echo "Starting GPU-enabled development environment..."
        docker compose up -d venom-dev
        docker compose exec venom-dev bash
        ;;
esac
