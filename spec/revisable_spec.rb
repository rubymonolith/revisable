# frozen_string_literal: true

RSpec.describe Revisable do
  let(:post) { Post.create!(title: nil, body: nil) }
  let(:user) { User.create!(name: "Alice") }
  let(:repo) { post.repository }

  describe "Blob" do
    it "content-addresses data by SHA" do
      blob1 = Revisable::Blob.store("hello")
      blob2 = Revisable::Blob.store("hello")
      expect(blob1.id).to eq(blob2.id)
      expect(blob1.sha).to eq(blob2.sha)
    end

    it "stores different content as different blobs" do
      blob1 = Revisable::Blob.store("hello")
      blob2 = Revisable::Blob.store("world")
      expect(blob1.sha).not_to eq(blob2.sha)
    end

    it "tracks byte size" do
      blob = Revisable::Blob.store("hello")
      expect(blob.size).to eq(5)
    end
  end

  describe "committing" do
    it "creates a first commit on main" do
      commit = repo.commit!(
        message: "First commit",
        fields: { title: "Hello", body: "World" }
      )

      expect(commit.sha).to be_present
      expect(commit.message).to eq("First commit")
      expect(commit.root?).to be true
    end

    it "chains commits with parent references" do
      c1 = repo.commit!(message: "First", fields: { title: "v1", body: "b1" })
      c2 = repo.commit!(message: "Second", fields: { title: "v2" })

      expect(c2.parent_shas).to eq([c1.sha])
      expect(c2.root?).to be false
    end

    it "carries forward unchanged fields" do
      repo.commit!(message: "First", fields: { title: "Hello", body: "World" })
      repo.commit!(message: "Update title only", fields: { title: "Updated" })

      snapshot = repo.at("main")
      expect(snapshot.title).to eq("Updated")
      expect(snapshot.body).to eq("World")
    end

    it "deduplicates identical blob content" do
      repo.commit!(message: "First", fields: { title: "Same", body: "Content" })
      repo.commit!(message: "Change and revert", fields: { title: "Different" })
      repo.commit!(message: "Revert", fields: { title: "Same" })

      expect(Revisable::Blob.where(data: "Same").count).to eq(1)
    end

    it "records the author" do
      commit = repo.commit!(
        message: "Authored commit",
        author: user,
        fields: { title: "Hi", body: "There" }
      )

      expect(commit.author).to eq(user)
    end
  end

  describe "branches" do
    before do
      repo.commit!(message: "Initial", fields: { title: "Hello", body: "World" })
    end

    it "lists branches as Branch objects" do
      branches = repo.branches
      expect(branches.size).to eq(1)
      expect(branches.first).to be_a(Revisable::Branch)
      expect(branches.first.name).to eq("main")
    end

    it "creates a branch from main" do
      branch = repo.branch!("draft", from: "main")
      expect(branch).to be_a(Revisable::Branch)
      expect(branch.name).to eq("draft")
      expect(repo.branches.map(&:name)).to contain_exactly("main", "draft")
    end

    it "branches share the same commit initially" do
      repo.branch!("draft", from: "main")
      expect(repo.at("main").title).to eq(repo.at("draft").title)
    end

    it "diverges after committing to a branch" do
      repo.branch!("draft", from: "main")

      repo.commit!(branch: "draft", message: "Draft edit", fields: { title: "Draft Title" })

      expect(repo.at("main").title).to eq("Hello")
      expect(repo.at("draft").title).to eq("Draft Title")
    end
  end

  describe "tags" do
    before do
      repo.commit!(message: "Initial", fields: { title: "v1 Title", body: "v1 Body" })
    end

    it "creates a tag" do
      tag = repo.tag!("v1", ref: "main", message: "First release")
      expect(tag).to be_a(Revisable::Tag)
      expect(tag.name).to eq("v1")
      expect(tag.message).to eq("First release")
      expect(tag.commit).to be_a(Revisable::Commit)
      expect(repo.tags.map(&:name)).to eq(["v1"])
    end

    it "tags are immutable snapshots" do
      repo.tag!("v1", ref: "main")
      repo.commit!(message: "Update", fields: { title: "v2 Title" })

      expect(repo.at("v1").title).to eq("v1 Title")
      expect(repo.at("main").title).to eq("v2 Title")
    end
  end

  describe "snapshots" do
    before do
      repo.commit!(message: "Initial", fields: { title: "Hello", body: "# World" })
    end

    it "responds to field names" do
      snapshot = repo.at("main")
      expect(snapshot.title).to eq("Hello")
      expect(snapshot.body).to eq("# World")
    end

    it "supports hash-style access" do
      snapshot = repo.at("main")
      expect(snapshot[:title]).to eq("Hello")
    end

    it "converts to a hash" do
      snapshot = repo.at("main")
      expect(snapshot.to_h).to eq({ title: "Hello", body: "# World" })
    end

    it "exposes the commit" do
      snapshot = repo.at("main")
      expect(snapshot.commit).to be_a(Revisable::Commit)
    end
  end

  describe "log" do
    it "returns a Log object" do
      repo.commit!(message: "First", fields: { title: "a", body: "b" })
      log = repo.log("main")
      expect(log).to be_a(Revisable::Log)
    end

    it "returns commits newest first" do
      c1 = repo.commit!(message: "First", fields: { title: "a", body: "b" })
      c2 = repo.commit!(message: "Second", fields: { title: "c" })
      c3 = repo.commit!(message: "Third", fields: { title: "d" })

      log = repo.log("main")
      expect(log.map(&:sha)).to eq([c3.sha, c2.sha, c1.sha])
    end

    it "respects limit" do
      repo.commit!(message: "First", fields: { title: "a", body: "b" })
      repo.commit!(message: "Second", fields: { title: "c" })
      repo.commit!(message: "Third", fields: { title: "d" })

      expect(repo.log("main", limit: 2).size).to eq(2)
    end

    it "renders text log" do
      repo.commit!(message: "First", fields: { title: "a", body: "b" })
      repo.commit!(message: "Second", fields: { title: "c" })

      text = repo.log("main").to_text
      expect(text).to include("Second")
      expect(text).to include("First")
    end

    it "is enumerable" do
      repo.commit!(message: "First", fields: { title: "a", body: "b" })
      repo.commit!(message: "Second", fields: { title: "c" })

      messages = repo.log("main").map(&:message)
      expect(messages).to eq(["Second", "First"])
    end
  end

  describe "diff" do
    before do
      repo.commit!(message: "Initial", fields: { title: "Hello", body: "World" })
      repo.branch!("edits", from: "main")
      repo.commit!(branch: "edits", message: "Edit body", fields: { body: "New World" })
    end

    it "detects changed and unchanged fields" do
      diff = repo.diff("main", "edits")

      expect(diff.field(:title).status).to eq(:unchanged)
      expect(diff.field(:body).status).to eq(:modified)
      expect(diff.changed_fields.map(&:field_name)).to eq([:body])
    end

    it "reports changed? correctly" do
      diff = repo.diff("main", "edits")
      expect(diff.changed?).to be true

      same_diff = repo.diff("main", "main")
      expect(same_diff.changed?).to be false
    end

    it "renders text diff" do
      diff = repo.diff("main", "edits")
      text = diff.field(:body).to_text

      expect(text).to include("--- a/body")
      expect(text).to include("+++ b/body")
      expect(text).to include("-World")
      expect(text).to include("+New World")
    end

    it "renders HTML diff" do
      diff = repo.diff("main", "edits")
      html = diff.field(:body).to_html

      expect(html).to include("<del>World</del>")
      expect(html).to include("<ins>New World</ins>")
      expect(html).to include('class="revisable-diff"')
    end

    it "returns nil for unchanged fields" do
      diff = repo.diff("main", "edits")
      expect(diff.field(:title).to_text).to be_nil
      expect(diff.field(:title).to_html).to be_nil
    end

    it "renders a combined text diff" do
      diff = repo.diff("main", "edits")
      expect(diff.to_text).to include("-World")
    end

    it "renders a combined HTML diff" do
      diff = repo.diff("main", "edits")
      expect(diff.to_html).to include("<del>")
    end
  end

  describe "merge" do
    before do
      repo.commit!(message: "Initial", fields: { title: "Hello", body: "World" })
      repo.branch!("feature", from: "main")
    end

    context "clean merge (no conflicts)" do
      before do
        repo.commit!(branch: "main", message: "Update title", fields: { title: "Updated Title" })
        repo.commit!(branch: "feature", message: "Update body", fields: { body: "New Body" })
      end

      it "auto-resolves non-conflicting changes" do
        merge = repo.merge("feature", into: "main")

        expect(merge.clean?).to be true
        expect(merge.auto_resolved.map(&:field_name)).to contain_exactly(:title, :body)
        expect(merge.conflicts).to be_empty
      end

      it "exposes branch names" do
        merge = repo.merge("feature", into: "main")
        expect(merge.into).to eq("main")
        expect(merge.from).to eq("feature")
      end

      it "can commit a clean merge" do
        merge = repo.merge("feature", into: "main")
        commit = merge.commit!(repository: repo, author: user, message: "Merge feature")

        expect(commit.merge?).to be true
        expect(commit.parent_shas.size).to eq(2)
      end

      it "advances the target branch" do
        merge = repo.merge("feature", into: "main")
        commit = merge.commit!(repository: repo, author: user, message: "Merge feature")

        snapshot = repo.at("main")
        expect(snapshot.title).to eq("Updated Title")
        expect(snapshot.body).to eq("New Body")
        expect(repo.log("main").first.sha).to eq(commit.sha)
      end
    end

    context "conflicting merge" do
      before do
        repo.commit!(branch: "main", message: "Main edit", fields: { body: "Main body" })
        repo.commit!(branch: "feature", message: "Feature edit", fields: { body: "Feature body" })
      end

      it "detects conflicts" do
        merge = repo.merge("feature", into: "main")

        expect(merge.clean?).to be false
        expect(merge.conflicts.map(&:field_name)).to include(:body)
      end

      it "provides conflict details by branch name" do
        merge = repo.merge("feature", into: "main")
        field = merge.field(:body)

        expect(field).to be_a(Revisable::MergeField)
        expect(field.status).to eq(:conflicted)
        expect(field.conflicted?).to be true
        expect(field.version("main")).to eq("Main body")
        expect(field.version("feature")).to eq("Feature body")
        expect(field.ancestor).to eq("World")
        expect(field.versions).to eq({ "main" => "Main body", "feature" => "Feature body" })
      end

      it "resolves with explicit content" do
        merge = repo.merge("feature", into: "main")
        merge.resolve(:body, "Manually merged body")

        expect(merge.all_resolved?).to be true
        expect(merge.field(:body).resolved?).to be true
        expect(merge.field(:body).resolved_value).to eq("Manually merged body")
      end

      it "resolves by branch name" do
        merge = repo.merge("feature", into: "main")
        merge.resolve(:body, "main")

        expect(merge.field(:body).resolved_value).to eq("Main body")
      end

      it "resolves with the other branch" do
        merge = repo.merge("feature", into: "main")
        merge.resolve(:body, "feature")

        expect(merge.field(:body).resolved_value).to eq("Feature body")
      end

      it "raises on commit with unresolved conflicts" do
        merge = repo.merge("feature", into: "main")

        expect {
          merge.commit!(repository: repo, message: "Bad merge")
        }.to raise_error(Revisable::UnresolvedConflictsError)
      end

      it "commits after resolving all conflicts" do
        merge = repo.merge("feature", into: "main")
        merge.resolve(:body, "Resolved content")

        commit = merge.commit!(repository: repo, author: user, message: "Resolved merge")

        expect(commit).to be_present
        expect(commit.merge?).to be true
      end
    end

    context "both changed to same value" do
      before do
        repo.commit!(branch: "main", message: "Main edit", fields: { body: "Same content" })
        repo.commit!(branch: "feature", message: "Feature edit", fields: { body: "Same content" })
      end

      it "auto-resolves when both sides agree" do
        merge = repo.merge("feature", into: "main")
        expect(merge.clean?).to be true
        expect(merge.auto_resolved.map(&:field_name)).to include(:body)
      end
    end
  end

  describe "publish" do
    it "materializes a tagged version to the model" do
      repo.commit!(message: "First", fields: { title: "Draft Title", body: "Draft Body" })
      repo.tag!("v1", ref: "main")

      repo.commit!(message: "More edits", fields: { title: "Newer Title" })

      repo.publish!("v1")

      post.reload
      expect(post.title).to eq("Draft Title")
      expect(post.body).to eq("Draft Body")
    end

    it "publishes latest tag by default" do
      repo.commit!(message: "First", fields: { title: "v1 Title", body: "v1 Body" })
      repo.tag!("v1", ref: "main")

      repo.commit!(message: "Second", fields: { title: "v2 Title" })
      repo.tag!("v2", ref: "main")

      repo.publish!

      post.reload
      expect(post.title).to eq("v2 Title")
    end

    it "raises without any tags" do
      repo.commit!(message: "First", fields: { title: "Hello", body: "World" })

      expect { repo.publish! }.to raise_error(Revisable::RefNotFoundError)
    end
  end

  describe "revisable DSL" do
    it "defines revisable_fields on the class" do
      expect(Post.revisable_fields).to eq([:title, :body])
    end

    it "provides a repository method" do
      expect(post.repository).to be_a(Revisable::Repository)
    end

    it "returns the same repository instance" do
      expect(post.repository).to be(post.repository)
    end
  end

  describe "auto-commit on save" do
    it "creates an initial commit on create" do
      new_post = Post.create!(title: "Auto Title", body: "Auto Body")
      log = new_post.repository.log("main")

      expect(log.size).to eq(1)
      expect(log.first.message).to eq("Initial version")
    end

    it "auto-commits on update" do
      new_post = Post.create!(title: "Original", body: "Body")
      new_post.update!(title: "Changed")

      log = new_post.repository.log("main")
      expect(log.size).to eq(2)
      expect(log.first.message).to include("title")
    end

    it "does not auto-commit when non-versionable fields change" do
      new_post = Post.create!(title: "Hello", body: "World")
      new_post.update!(created_at: 1.day.ago)

      log = new_post.repository.log("main")
      expect(log.size).to eq(1)
    end

    it "snapshot matches current model state" do
      new_post = Post.create!(title: "Hello", body: "World")
      new_post.update!(title: "Updated")

      snapshot = new_post.repository.at("main")
      expect(snapshot.title).to eq("Updated")
      expect(snapshot.body).to eq("World")
    end
  end

  describe "CurrentAuthor" do
    it "tracks the current author via thread-local" do
      Revisable::CurrentAuthor.set(user)
      expect(Revisable::CurrentAuthor.get).to eq(user)
      Revisable::CurrentAuthor.clear
    end

    it "scopes author to a block" do
      Revisable::CurrentAuthor.with(user) do
        expect(Revisable::CurrentAuthor.get).to eq(user)
      end
      expect(Revisable::CurrentAuthor.get).to be_nil
    end

    it "auto-commits with the current author" do
      Revisable::CurrentAuthor.with(user) do
        new_post = Post.create!(title: "Authored", body: "Content")
        commit = new_post.repository.log("main").first
        expect(commit.author).to eq(user)
      end
    end

    it "restores previous author after block" do
      other_user = User.create!(name: "Bob")
      Revisable::CurrentAuthor.set(other_user)

      Revisable::CurrentAuthor.with(user) do
        expect(Revisable::CurrentAuthor.get).to eq(user)
      end

      expect(Revisable::CurrentAuthor.get).to eq(other_user)
      Revisable::CurrentAuthor.clear
    end
  end
end
