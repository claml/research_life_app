# AI Development Guide

## Project Collaboration Rules

- `main` / `master` only contains stable code.
- `develop` is the integration branch.
- `feature/*` is for product features.
- `fix/*` is for bug fixes.
- `chore/*` is for docs, tooling, config, and collaboration rules.
- Do not push directly to `main`, `master`, or `develop`.
- All changes should be merged through Pull Requests.

## AI Working Rules

- Read this file before editing code.
- **System documentation:** The merged project overview lives at `research-life-backend/docs/README.md`. When you add a feature and the repository file tree changes (new `features/`, `services/`, `module/` packages, or top-level directories), update **§2 功能总览** and **§3 仓库与目录结构** in that file in the same PR.
- Keep changes scoped to the requested task.
- Do not rewrite unrelated modules.
- Do not introduce new dependencies unless the reason is explained.
- Do not change public APIs without updating related docs and tests.
- Do not commit secrets, private keys, local config, logs, build outputs, or generated cache files.
- Before submitting, summarize what changed, why it changed, affected files, checks run, and remaining risks.

## Frontend Rules

- Technology: Flutter / Dart.
- Use existing project structure.
- Feature UI goes under `应用/lib/features/<feature>/`.
- Business services go under `应用/lib/services/<domain>/`.
- Shared widgets go under `应用/lib/shared/`.
- Avoid expanding `ResearchLifeController` unless the logic coordinates multiple features.
- Prefer feature-specific controllers for new feature state.
- Keep page files reasonably small. If a page grows too large, split widgets or state logic into separate files.
- Run `dart format .` and `flutter analyze` before creating a Pull Request when frontend code changes.

## Backend Rules

- Technology: Spring Boot / Java 8 / MyBatis-Plus / MySQL / Redis / Flyway.
- Controller only handles request mapping, parameter validation, and response wrapping.
- Service contains business logic.
- Mapper only handles persistence.
- Public API responses should use explicit DTOs instead of `Map<String, Object>`.
- Do not use `System.out` or `printStackTrace`.
- Use logger for diagnostics.
- Do not edit existing Flyway migration files after they have been shared. Add a new `Vx__description.sql` migration instead.
- Do not commit real database passwords, JWT secrets, MinIO keys, SSH keys, or local-only config.

## Review Checklist

Before opening a Pull Request, confirm:

- The change matches the branch purpose.
- Unrelated files were not modified.
- Formatting and basic checks were run where possible.
- Risky behavior changes are explained in the PR.
- Any AI-generated code was reviewed by a human.