.PHONY: help context context-contracts context-sdk context-demo format \
    check-format test build clean dev install deploy devnet-up devnet-down devnet-e2e

help:
	@echo "Context generation commands:"
	@echo "  make context           - Generate full project context"
	@echo "  make context-contracts - Generate Cairo contracts context"
	@echo "  make context-sdk       - Generate TypeScript SDK context"
	@echo "  make context-demo      - Generate demo frontend context"
	@echo ""
	@echo "Development commands:"
	@echo "  make build             - Build Cairo contracts"
	@echo "  make test              - Run all tests"
	@echo "  make format            - Format Cairo code"
	@echo "  make check-format      - Check formatting without modifying"
	@echo ""
	@echo "Demo commands:"
	@echo "  make dev               - Start demo server (localhost:8080)"
	@echo "  make devnet-up         - Start local devnet"
	@echo "  make devnet-down       - Stop local devnet"
	@echo "  make devnet-e2e        - Run local devnet end-to-end flow"
	@echo "  make install           - Install SDK dependencies"
	@echo ""
	@echo "Deployment commands:"
	@echo "  make deploy            - Deploy contracts to Sepolia"
	@echo ""
	@echo "Cleanup commands:"
	@echo "  make clean             - Remove build artifacts and context files"

# Context generation
context:
	@echo "Generating full project context..."
	@DATE=$$(date '+%Y-%m-%d_%H-%M-%S_%Z'); \
	OUTPUT_FILE="context-full-$${DATE}.xml"; \
	cp repomix.config.json repomix.config.json.bak && \
	jq ".output.filePath = \"$$OUTPUT_FILE\"" repomix.config.json > repomix.config.json.tmp && \
	mv repomix.config.json.tmp repomix.config.json && \
	(repomix --config repomix.config.json || (mv repomix.config.json.bak repomix.config.json && exit 1)) && \
	mv repomix.config.json.bak repomix.config.json && \
	rm -f repomix.config.json.tmp && \
	echo "[OK] Context written to $$OUTPUT_FILE"

context-contracts:
	@echo "Generating Cairo contracts context..."
	@DATE=$$(date '+%Y-%m-%d_%H-%M-%S_%Z'); \
	OUTPUT_FILE="context-contracts-$${DATE}.xml"; \
	cp repomix.config.json repomix.config.json.bak && \
	jq --arg file "$$OUTPUT_FILE" \
	  '.output.filePath = $$file | .include = ["src/**", "tests/**", "Scarb.toml", "Scarb.lock", "snfoundry.toml", "SNIP.md", "README.md"]' \
	  repomix.config.json > repomix.config.json.tmp && \
	mv repomix.config.json.tmp repomix.config.json && \
	(repomix --config repomix.config.json || (mv repomix.config.json.bak repomix.config.json && exit 1)) && \
	mv repomix.config.json.bak repomix.config.json && \
	rm -f repomix.config.json.tmp && \
	echo "[OK] Context written to $$OUTPUT_FILE"

context-sdk:
	@echo "Generating SDK context..."
	@DATE=$$(date '+%Y-%m-%d_%H-%M-%S_%Z'); \
	OUTPUT_FILE="context-sdk-$${DATE}.xml"; \
	cp repomix.config.json repomix.config.json.bak && \
	jq --arg file "$$OUTPUT_FILE" \
	  '.output.filePath = $$file | .include = ["sdk/**", "scripts/**", "deployments/**", "README.md", "SNIP.md"]' \
	  repomix.config.json > repomix.config.json.tmp && \
	mv repomix.config.json.tmp repomix.config.json && \
	(repomix --config repomix.config.json || (mv repomix.config.json.bak repomix.config.json && exit 1)) && \
	mv repomix.config.json.bak repomix.config.json && \
	rm -f repomix.config.json.tmp && \
	echo "[OK] Context written to $$OUTPUT_FILE"

context-demo:
	@echo "Generating demo frontend context..."
	@DATE=$$(date '+%Y-%m-%d_%H-%M-%S_%Z'); \
	OUTPUT_FILE="context-demo-$${DATE}.xml"; \
	cp repomix.config.json repomix.config.json.bak && \
	jq --arg file "$$OUTPUT_FILE" \
	  '.output.filePath = $$file | .include = ["demo/**", "deployments/**", "README.md"]' \
	  repomix.config.json > repomix.config.json.tmp && \
	mv repomix.config.json.tmp repomix.config.json && \
	(repomix --config repomix.config.json || (mv repomix.config.json.bak repomix.config.json && exit 1)) && \
	mv repomix.config.json.bak repomix.config.json && \
	rm -f repomix.config.json.tmp && \
	echo "[OK] Context written to $$OUTPUT_FILE"

# Development
build:
	@echo "Building Cairo contracts..."
	@scarb build

test:
	@echo "Running Cairo tests..."
	@snforge test

format:
	@echo "Formatting Cairo code..."
	@scarb fmt

check-format:
	@echo "Checking Cairo formatting..."
	@scarb fmt --check

# Demo
dev:
	@echo "Starting demo server on http://localhost:8080..."
	@cd demo && python3 -m http.server 8080

devnet-e2e:
	@echo "Running devnet end-to-end flow..."
	@cd scripts/devnet-e2e && ./run-devnet-e2e.sh

devnet-up:
	@cd scripts/devnet-e2e && ./start-devnet.sh

devnet-down:
	@cd scripts/devnet-e2e && ./stop-devnet.sh

install:
	@echo "Installing SDK dependencies..."
	@cd sdk && npm install
	@cd scripts/deploy-js && npm install
	@cd scripts/demo && npm install

# Deployment
deploy:
	@echo "Deploying contracts to Sepolia..."
	@cd scripts/deploy-js && npx tsx deploy.ts

# Cleanup
clean:
	@echo "Cleaning generated files..."
	@rm -f context*.xml
	@rm -f context-*.xml
	@rm -f repomix.config.json.bak
	@rm -f repomix.config.json.tmp
	@rm -rf target
	@rm -rf sdk/node_modules
	@rm -rf scripts/*/node_modules
	@echo "[OK] Cleanup complete"
