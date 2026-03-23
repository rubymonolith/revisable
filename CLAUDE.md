# Revisable

Git-like content versioning for ActiveRecord. Branches, merges, diffs, tags, publishing.

## Quick reference

```bash
bundle exec rspec              # run tests (sqlite in-memory, no setup needed)
ruby examples/post.rb          # interactive demo
```

## Architecture

Two layers:

1. **Core objects** (no AR dependency) — `FieldSet`, `Snapshot`, `FieldDiff`, `Diff`, `MergeField`, `Merge`, `Log`, renderers
2. **AR integration** — `Blob`, `Commit`, `CommitField`, `CommitParent`, `Ref`, `Repository`, `Model` concern, `CurrentAuthor`, `ControllerHelpers`

Core objects use duck typing. They work with anything that responds to the right methods (`.sha`, `.data`, `.field_set`, etc). AR models implement those interfaces.

## Key design decisions

- **Full state per commit, not deltas.** Each commit stores a blob SHA for every revisable field. Unchanged fields reuse the same blob SHA (deduped). This means any commit can be read without walking history.
- **Field-level conflict detection.** Merges conflict when both sides changed the same field. No line-level merge — resolution is always "here's the final string for this field."
- **Merge versions are keyed by branch name**, not ours/theirs. `field.version("main")`, `field.resolve("amy-draft")`.
- **`into` / `from`** — merge terminology mirrors the method call: `repo.merge("feature", into: "main")` → `merge.into`, `merge.from`.
- **Auto-commit on save** via `after_create`/`after_update`. Disable with `revisable :title, :body, auto_commit: false`.
- **Everything returns objects**, not strings/symbols/hashes. `repo.branches` returns `[Branch]`, `merge.conflicts` returns `[MergeField]`, etc. Strings are input-only (ref names, SHAs).

## Table prefix

All tables are prefixed `revisable_` (blobs, commits, commit_parents, commit_fields, refs).

## Tests

Specs use SQLite in-memory with transaction rollback per example. No external dependencies. The `Post` and `User` test models are defined in `spec/spec_helper.rb`.
