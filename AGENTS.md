# Repository workflow

- Start every new feature from an up-to-date `main` on `feat/<short-name>`.
- Use `fix/`, `refactor/`, `docs/`, `test/`, or `chore/` branches for other work.
- Do not implement new features directly on `main`. The initial import is the only bootstrap exception.
- Commit format: `<type>(<part>): <description>`.
- Types: `feat`, `fix`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `perf`, `revert`.
- Parts describe the boundary: `app`, `runtime`, `core`, `bridge`, `mods`, `records`, `docs`, `repo`, `ci`.
- Keep commits coherent and reviewable. Preserve feature branches and use pull requests.
- Update the architecture and installation docs when public behavior or module boundaries change.
- Run checks appropriate to changes; hardware tests are explicit, separate from offline checks.
- Never commit Steam data, Wine prefixes, game assets, user presets, logs, credentials, or downloaded runtime binaries.
- Preserve existing CrossOver environments during runtime migrations. New runtimes use isolated prefixes.
- Third-party runtime downloads must have a pinned version, source URL, checksum, and license attribution.
- Keep native HID output in MozaKit. UI, archive installation, and runtime setup must not send arbitrary device reports.
- Follow `docs/development.md` for setup, testing, and branch conventions.
