.PHONY: help install lint lint-fix lint-all format format-all check clean

# Show available commands
help:
	@echo "Available commands:"
	@echo ""
	@echo "  Setup:"
	@echo "    make install     Sync dependencies with uv (creates .venv)"
	@echo ""
	@echo "  Code Quality (custom files only, ignores upstream code):"
	@echo "    make lint        Lint your custom files vs main (read-only)"
	@echo "    make lint-fix    Lint your custom files with auto-fix"
	@echo "    make format      Format your custom files with ruff"
	@echo "    make check       format --check + lint on custom files (CI-friendly)"
	@echo ""
	@echo "  Whole codebase (use sparingly — auto-fix will conflict with upstream):"
	@echo "    make lint-all    Lint entire repo (read-only)"
	@echo "    make format-all  Format entire repo"
	@echo ""
	@echo "  Maintenance:"
	@echo "    make clean       Clean cache files"

# Sync dependencies with uv (includes dev group by default)
install:
	@echo "📦 Syncing dependencies with uv..."
	@uv sync

# Resolve "custom files" = Python files that differ from main + untracked new files.
# Deletions are filtered out so ruff doesn't error on missing paths.
_custom_files = $$( { \
    git diff --name-only --diff-filter=AM main -- '*.py' 2>/dev/null; \
    git ls-files --others --exclude-standard -- '*.py' 2>/dev/null; \
  } | sort -u )

# Lint only your custom changes (does not touch upstream files)
lint:
	@files=$(_custom_files); \
	if [ -z "$$files" ]; then \
	  echo "✨ No custom Python files vs main. Nothing to lint."; \
	else \
	  echo "🔍 Linting custom files:"; echo "$$files" | sed 's/^/  - /'; \
	  uv run ruff check $$files; \
	fi

# Auto-fix on custom changes only
lint-fix:
	@files=$(_custom_files); \
	if [ -z "$$files" ]; then \
	  echo "✨ No custom Python files vs main."; \
	else \
	  echo "🔧 Lint-fixing custom files:"; echo "$$files" | sed 's/^/  - /'; \
	  uv run ruff check --fix $$files; \
	fi

# Format custom changes only
format:
	@files=$(_custom_files); \
	if [ -z "$$files" ]; then \
	  echo "✨ No custom Python files vs main."; \
	else \
	  echo "🎨 Formatting custom files:"; echo "$$files" | sed 's/^/  - /'; \
	  uv run ruff format $$files; \
	fi

# CI-friendly check (no mutation)
check:
	@files=$(_custom_files); \
	if [ -z "$$files" ]; then \
	  echo "✨ No custom Python files vs main. Nothing to check."; \
	else \
	  echo "🎨 Checking format on custom files:"; echo "$$files" | sed 's/^/  - /'; \
	  uv run ruff format --check $$files && \
	  echo "🔍 Linting custom files..." && \
	  uv run ruff check $$files; \
	fi

# Inspect entire repo (read-only) — useful for triage, not for fixing
lint-all:
	@echo "🔍 Linting WHOLE codebase (read-only)..."
	@uv run ruff check .

# Format entire repo — WARNING: will create big diff with upstream, rebases will hurt
format-all:
	@echo "⚠️  Formatting WHOLE codebase. This will conflict with upstream pulls."
	@uv run ruff format .

# Clean cache files
clean:
	@echo "🧹 Cleaning cache files..."
	@find . -type d -name "__pycache__" -not -path "./.venv/*" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".ruff_cache" -not -path "./.venv/*" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -not -path "./.venv/*" -delete 2>/dev/null || true
	@echo "✅ Cache cleaned!"
