# Revisable

Git-like versioning for ActiveRecord text content. Branches, merges, diffs, tags, and publishing — in your database.

## Why not PaperTrail / Audited / Logidze?

Every existing Rails versioning gem gives you a **linear audit log**. That's fine for tracking "who changed what when," but it falls apart when you need real content workflows:

| | PaperTrail | Audited | Logidze | **Revisable** |
|---|---|---|---|---|
| Branching | No | No | No | **Yes** |
| Merging | No | No | No | **Yes** |
| Diffing | Adjacent only | No | Between versions | **Any two refs** |
| Tags / named versions | No | No | No | **Yes** |
| Content deduplication | No | No | No | **SHA-based** |
| Publish workflow | No | No | No | **Tag → publish** |
| Storage model | Full snapshots | After-state | Incremental JSON | **Content-addressed blobs** |

PaperTrail and friends answer "what happened?" Revisable answers "what's the state of this content, on this branch, and how does it differ from that branch?"

### When to use Revisable

You're building a CMS, docs site, legal document system, or any app where **content goes through drafts, review, and publishing**. Multiple people might edit the same article. You want to see diffs, branch off drafts, and tag releases.

### When to use PaperTrail

You want an audit log for compliance. You need to know that `user_42` changed `price` from `19.99` to `24.99` at 3:47pm. Linear history is fine. You don't need branches or diffs.

## Installation

Add to your Gemfile:

```ruby
gem "revisable"
```

Generate the migration:

```bash
rails generate revisable:install
rails db:migrate
```

## Setup

```ruby
class Post < ApplicationRecord
  include Revisable::Model
  revisable :title, :body
end
```

That's it. Any text/string columns you pass to `revisable` get git-like version control.

## ActiveRecord Integration

### Auto-commit on save

Revisable hooks into `after_create` and `after_update`. When you save a model with revisable fields, a commit is created automatically:

```ruby
post = Post.create!(title: "First Draft", body: "Hello world")
# => auto-creates initial commit on "main"

post.update!(title: "Better Title")
# => auto-creates commit "Updated title" on "main"

post.repository.log("main").map(&:message)
# => ["Updated title", "Initial version"]
```

To disable auto-commit (for models where you want manual control):

```ruby
class LegalDocument < ApplicationRecord
  include Revisable::Model
  revisable :content, :summary, auto_commit: false
end
```

### Author tracking

Set the current author in your controller so auto-commits know who made the change:

```ruby
class ApplicationController < ActionController::Base
  include Revisable::ActiveRecord::ControllerHelpers

  private

  def revisable_author
    current_user
  end
end
```

Now every save within a request automatically records the author:

```ruby
post.update!(title: "New Title")
post.repository.log("main").first.author  # => #<User id: 1, name: "Alice">
```

You can also set the author explicitly for background jobs or console work:

```ruby
Revisable::CurrentAuthor.with(admin_user) do
  post.update!(body: "Bulk-edited content")
end
```

## Usage

### Manual commits

For more control, use the repository directly. Pass only the fields that changed — unchanged fields carry forward automatically.

```ruby
repo = post.repository

repo.commit!(
  message: "First draft",
  author: current_user,
  fields: { title: "How to Deploy Rails", body: "# Step 1\n..." }
)

# Later, update just the body
repo.commit!(
  message: "Added step 2",
  author: current_user,
  fields: { body: "# Step 1\n...\n# Step 2\n..." }
)
```

Content is stored as SHA-256 addressed blobs. If you revert a title to a previous value, no new storage is used — it points to the existing blob.

### Reading

```ruby
# Read current state of any branch or tag
snapshot = repo.at("main")
snapshot.title  # => "How to Deploy Rails"
snapshot.body   # => "# Step 1\n..."
snapshot.to_h   # => { title: "...", body: "..." }

# Read by tag or SHA
repo.at("v2").title
repo.at("abc123").title
```

### Branching

```ruby
repo.branch!("amy-draft", from: "main")

repo.commit!(
  branch: "amy-draft",
  message: "Rewrote intro",
  author: amy,
  fields: { body: "# Better intro\n..." }
)

# main is untouched
repo.at("main").body   # => original
repo.at("amy-draft").body  # => rewritten
```

### Diffing

Compare any two refs, commits, or tags. Diffs are field-level — blob SHAs are compared first, so unchanged fields skip text diffing entirely.

```ruby
diff = repo.diff("main", "amy-draft")

diff.changed?           # => true
diff.changed_fields     # => [:body]

diff.field(:title).status  # => :unchanged
diff.field(:body).status   # => :modified

# Unified text diff (like `git diff`)
puts diff.field(:body).to_text
# --- a/body
# +++ b/body
# -# Step 1
# +# Better intro

# HTML diff (for web UIs)
diff.field(:body).to_html
# <div class="revisable-diff" data-field="body">
#   <del># Step 1</del>
#   <ins># Better intro</ins>
# </div>

# Combined diff across all fields
diff.to_text
diff.to_html
```

### Merging

Three-way merge using the common ancestor. Fields that only changed on one side auto-resolve. Fields changed on both sides are conflicts.

```ruby
merge = repo.merge("amy-draft", into: "main")

merge.clean?        # => false
merge.conflicts     # => [:body]
merge.auto_resolved # => [:title]

# Inspect a conflict — each field is a MergeField object
field = merge.field(:body)
field.status      # => :conflicted
field.ours        # => main's version
field.theirs      # => amy-draft's version
field.ancestor    # => common ancestor

# Resolve it (on the field directly, or via the merge)
field.resolve("hand-written resolution")
field.resolve(:ours)     # pick main's version
field.resolve(:theirs)   # pick amy's version

# Or resolve all conflicts at once
merge.each do |name, f|
  f.resolve(:theirs) if f.conflicted?
end

# Commit the merge (creates a two-parent commit)
merge.commit!(repository: repo, author: current_user, message: "Merged Amy's draft")
```

### Tags and publishing

Tags are immutable pointers to a commit. Publishing materializes a tag's content into the model's actual columns — so your views and APIs read plain ActiveRecord attributes with zero versioning overhead.

```ruby
# Tag the current state of main
repo.tag!("v1", ref: "main", message: "Launch version")

# More editing happens on main...
repo.commit!(message: "Post-launch tweaks", fields: { body: "..." })

# Readers still see v1 until you publish
repo.publish!("v1")

# post.title and post.body now reflect v1
# Your views just do: @post.title — no versioning API needed

# Publish latest tag
repo.publish!
```

### Log

```ruby
log = repo.log("main")              # => Log (Enumerable)
log = repo.log("main", limit: 10)   # => last 10

# Log is enumerable
log.map(&:message)    # => ["Added step 2", "First draft"]
log.first             # => most recent Commit
log.to_text           # => "* a1b2c3 Added step 2\n* f4e5d6 First draft"

# Commit objects
commit = log.first
commit.sha            # => "a1b2c3..."
commit.message        # => "Added step 2"
commit.author         # => #<User id: 1, name: "Alice">
commit.committed_at   # => 2026-03-21 14:30:00 UTC
commit.parents        # => [#<Commit ...>]
commit.merge?         # => false
commit.root?          # => false
```

## How it works

Revisable uses the same conceptual model as git, minus the parts you don't need in a database:

| Git concept | Revisable equivalent | Notes |
|---|---|---|
| Blob | `revisable_blobs` | SHA-256 content-addressed. Identical content = one row. |
| Tree | — | Skipped. Fields are flat, not nested directories. |
| Commit | `revisable_commits` | Polymorphic author, parent links, scoped to a record. |
| Tree entries | `revisable_commit_fields` | Each commit stores a blob SHA for every revisable field. |
| Ref | `revisable_refs` | Branches and tags. Compare-and-swap updates for concurrency. |
| Packfile | — | Not needed. Postgres handles storage. |
| Index / staging | — | Not needed. Every `commit!` is direct. |

Each commit stores **full state** (a blob SHA for every field), not deltas. This means you can read any commit without walking history. Unchanged fields reuse the same blob SHA, so storage cost is minimal.

## Schema

Revisable creates 5 tables. Run `rails generate revisable:install` to get the migration:

- **`revisable_blobs`** — content-addressed text storage
- **`revisable_commits`** — commit metadata, polymorphic to any model
- **`revisable_commit_parents`** — parent links (supports merge commits with 2+ parents)
- **`revisable_commit_fields`** — maps each commit × field to a blob
- **`revisable_refs`** — branches and tags per record

All tables are polymorphic — one set of tables serves every model that uses `revisable`.

## Concurrency

Branch refs use compare-and-swap updates. If two writers commit to the same branch simultaneously, the second one gets a `Revisable::StaleRefError` and can retry. At CMS-level write volumes this is rarely hit, but it's there.

## License

MIT
