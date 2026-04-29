terraform {
  required_version = ">= 1.5"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  owner = "HorseNuggets"
  # Authenticates via GITHUB_TOKEN environment variable
}

locals {
  repo_name = "pathline"

  required_checks = [
    "Test",
  ]
}

# Repository settings
resource "github_repository" "pathline" {
  name        = local.repo_name
  description = "Git-aware path display with worktree highlighting."
  visibility  = "public"

  has_issues   = true
  has_projects = false
  has_wiki     = false

  allow_squash_merge = true
  allow_merge_commit = false
  allow_rebase_merge = false

  delete_branch_on_merge = true

  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
}

# Branch protection for main
resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = github_repository.pathline.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    pull_request {
      required_approving_review_count = 0
      dismiss_stale_reviews_on_push   = true
    }

    copilot_code_review {
      review_on_push             = true
      review_draft_pull_requests = false
    }

    required_status_checks {
      dynamic "required_check" {
        for_each = local.required_checks
        content {
          context        = required_check.value
          integration_id = 0
        }
      }
    }
  }
}
