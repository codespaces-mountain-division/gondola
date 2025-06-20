# Documentation Drift Detection Actions

This directory contains GitHub Actions that automatically detect when documentation might be outdated due to code changes.

## Setup Required

**Important:** This workflow requires specific repository permissions and GitHub Copilot access.

See [SETUP_GUIDE.md](./SETUP_GUIDE.md) for complete setup instructions.

### Required Secrets & Permissions

- **GITHUB_TOKEN** - Automatically provided by GitHub Actions for repository operations
- **COPILOT_TOKEN** - Required for GitHub Copilot API access (see setup instructions below)
- **Repository Permissions** - Must enable "Read and write permissions" in repository Settings → Actions → General

### Copilot Token Setup

If you get "Authorization header is badly formatted" errors:

1. **Create a Personal Access Token:**
   - Go to GitHub.com → Settings → Developer settings → Personal access tokens → Fine-grained tokens
   - Create a new token with **"GitHub Copilot Chat"** permissions
   
2. **Add as Repository Secret:**
   - Go to your repository → Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `COPILOT_TOKEN`
   - Value: Your personal access token

3. **Alternative:** Use GitHub Copilot for Business/Enterprise tokens if available

## Quick Start

**Prerequisites:**
- GitHub Copilot access for your repository
- Repository permissions configured (see setup guide)

**Steps:**
1. Configure repository permissions in GitHub Settings
2. Commit these files to your repository  
3. Push documentation changes to create the knowledge base
4. Create pull requests to see drift detection in action

## What Gets Analyzed

The actions automatically detect and analyze:
- All Markdown files (`**/*.md`, `**/*.markdown`)
- README files (`**/README*`)
- Changelog files (`**/CHANGELOG*`) 
- Contributing guides (`**/CONTRIBUTING*`)

## Files

- `workflows/documentation-management.yml` - Main workflow
- `actions/docs-knowledge-base-updater/` - Classification action
- `actions/docs-drift-detective/` - Drift detection action
- `SETUP_GUIDE.md` - Complete setup instructions
