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

# Adopt the existing repository and ruleset instead of trying to create them. Import ids
# must be literal strings on Terraform 1.5.
import {
  to = github_repository.pathline
  id = "pathline"
}

import {
  to = github_repository_ruleset.main
  id = "pathline:15735746"
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
      required_approving_review_count = 1
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

# Keeps Copilot code review at the Lite effort level, which costs several times fewer AI
# credits than the Balanced default, and corrects drift on apply.
module "copilot_review" {
  source        = "https://github.com/horsenuggets/luau-cicd/archive/a342a72d078bca2ff7f529bff4a68a68743b313a.tar.gz//luau-cicd-a342a72d078bca2ff7f529bff4a68a68743b313a/Terraform/Modules/CopilotReview"
  repository    = github_repository.pathline.full_name
  review_effort = "lite"
}
