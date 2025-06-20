# Documentation Drift Detection Actions

This directory contains GitHub Actions that automatically detect when documentation might be outdated due to code changes.

## Setup Required

See [SETUP_GUIDE.md](./SETUP_GUIDE.md) for complete setup instructions.

## Quick Start

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
