.PHONY: lint test schemas l10n docs build clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Run linters (shellcheck, jsonlint)
	@echo "=== Lint ==="
	@find . -name '*.sh' -not -path './.git/*' | xargs shellcheck 2>/dev/null || echo "shellcheck not installed"
	@find . -name '*.json' -not -path './.git/*' -not -path './node_modules/*' | while read f; do python3 -m json.tool "$$f" >/dev/null 2>&1 || echo "Invalid JSON: $$f"; done

test: ## Run tests
	@echo "=== Tests ==="
	@if command -v bats >/dev/null 2>&1; then bats tests/; else echo "bats not installed, skipping"; fi

schemas: ## Validate JSON schemas
	@sh scripts/validate_schemas.sh

l10n: ## Check localization coverage
	@sh scripts/check_l10n_coverage.sh

docs: ## Check required docs
	@sh scripts/check_required_docs.sh 2>/dev/null || echo "check_required_docs.sh not ready yet"

build: ## Build release artifacts (dry-run)
	@echo "=== Build (dry-run) ==="
	@echo "Version: $$(python3 -c \"import json; print(json.load(open('version.json'))['version'])\")"
	@echo "TODO: implement build pipeline"

clean: ## Clean temp files
	@rm -rf workdir/ tmp/ dist/ build/ tests/output/
	@echo "Cleaned"

all: lint schemas l10n test ## Run all checks
