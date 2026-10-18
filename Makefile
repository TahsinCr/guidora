.PHONY: up down restart logs ps health test test-backend test-frontend build clean help

# Default target
all: help

help:
	@echo "Guidora Monorepo Management Commands:"
	@echo "  make up             Start the full production Docker stack"
	@echo "  make down           Stop all running services"
	@echo "  make restart        Restart the Docker stack"
	@echo "  make logs           Follow live container logs"
	@echo "  make ps             Display running containers and health status"
	@echo "  make health         Check backend readiness probe"
	@echo "  make test           Run all tests across backend and frontend submodules"
	@echo "  make test-backend   Run .NET 10 backend tests"
	@echo "  make test-frontend  Run React 18 Vitest frontend tests"
	@echo "  make build          Build frontend and backend production artifacts"
	@echo "  make clean          Stop stack and purge persistent volumes (PostgreSQL/Redis)"

up:
	./start-docker.sh

down:
	./stop-docker.sh

restart:
	./stop-docker.sh && ./start-docker.sh

logs:
	docker compose logs -f

ps:
	docker compose ps

health:
	@curl -s -f http://localhost/health/ready && echo "\nBackend is READY" || echo "\nBackend is NOT ready"

test: test-backend test-frontend

test-backend:
	dotnet test backend/Tests/Tests.csproj

test-frontend:
	cd frontend && npm test

build:
	cd frontend && npm run build
	dotnet build backend/NetCoreBackend.sln -c Release

clean:
	./stop-docker.sh --clean
