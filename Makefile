.PHONY: help up down restart logs build pull apk appbundle release

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

up: ## Start the Cashew server in Docker
	docker compose up -d

down: ## Stop the Cashew server
	docker compose down

restart: ## Restart the Cashew server
	docker compose restart

logs: ## Show server logs
	docker compose logs -f

build: ## Build the Cashew server Docker image
	docker compose build --no-cache

pull: ## Pull the latest published Docker image from GHCR
	docker compose pull

apk: ## Build the Android APK (requires Flutter SDK)
	cd budget && flutter build apk --release

appbundle: ## Build the Android App Bundle (requires Flutter SDK)
	cd budget && flutter build appbundle --release

release: ## Tag a new version and push it (usage: make release VERSION=v5.5.0)
ifndef VERSION
	$(error VERSION is required. Usage: make release VERSION=v5.5.0)
endif
	git tag $(VERSION)
	git push origin $(VERSION)
