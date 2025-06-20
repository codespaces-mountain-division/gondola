# Documentation Knowledge Base Updater

A GitHub Action that classifies documentation files in your repository and maintains a knowledge base for documentation drift detection.

## Features

- 🤖 **AI-Powered Classification**: Uses GitHub Copilot to analyze documentation files
- 📊 **Four-Dimensional Analysis**: Classifies docs by code sensitivity, staleness risk, technical patterns, and document type
- 💾 **Knowledge Base Generation**: Creates a structured JSON file with classification data
- 🔄 **Automatic Updates**: Keeps the knowledge base in sync with documentation changes

## Usage

### Basic Usage

```yaml
name: Update Documentation Knowledge Base
on:
  push:
    paths:
      - '**/*.md'
      - '**/*.markdown'
  pull_request:
    paths:
      - '**/*.md'
      - '**/*.markdown'

jobs:
  update-knowledge-base:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Update Documentation Knowledge Base
        uses: ./actions/docs-knowledge-base-updater
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          copilot-token: ${{ secrets.COPILOT_TOKEN }}
```

### Advanced Configuration

```yaml
- name: Update Documentation Knowledge Base
  uses: ./actions/docs-knowledge-base-updater
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    copilot-token: ${{ secrets.COPILOT_TOKEN }}
    knowledge-base-path: '.github/docs-knowledge-base.json'
    docs-patterns: |
      **/*.md
      **/*.markdown
      **/README*
      **/CHANGELOG*
      **/CONTRIBUTING*
      docs/**/*.rst
    exclude-patterns: |
      node_modules/**
      .git/**
      vendor/**
      .github/workflows/**
      test/**
      __tests__/**
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github-token` | GitHub token for API access | ✅ | `${{ github.token }}` |
| `copilot-token` | GitHub Copilot API token | ❌ | `${{ github.token }}` |
| `knowledge-base-path` | Path to store the knowledge base file | ❌ | `.github/docs-knowledge-base.json` |
| `docs-patterns` | File patterns to classify (newline-separated) | ❌ | `**/*.md`<br>`**/*.markdown`<br>`**/README*`<br>`**/CHANGELOG*`<br>`**/CONTRIBUTING*` |
| `exclude-patterns` | Patterns to exclude (newline-separated) | ❌ | `node_modules/**`<br>`.git/**`<br>`vendor/**`<br>`.github/workflows/**` |

## Outputs

| Output | Description |
|--------|-------------|
| `knowledge-base-path` | Path to the generated knowledge base file |
| `classified-files-count` | Number of files classified |
| `high-sensitivity-files` | Number of high code-sensitivity files found |

## Knowledge Base Structure

The generated knowledge base file contains:

```json
{
  "repository": "owner/repo",
  "generated_at": "2025-06-18T10:30:00Z",
  "total_files": 42,
  "avg_code_sensitivity": 1.8,
  "avg_staleness_risk": 2.1,
  "high_sensitivity_files": 8,
  "high_staleness_files": 12,
  "high_risk_files": 5,
  "files": [
    {
      "path": "docs/api.md",
      "sha": "abc123...",
      "code_sensitivity_level": 3,
      "staleness_risk": 3,
      "technical_patterns": ["API/Routing", "Authentication/Authorization"],
      "doc_category": "API Reference (Advanced)",
      "confidence_score": 0.92,
      "key_indicators": ["function signatures", "endpoint documentation"],
      "classified_at": "2025-06-18T10:30:00Z"
    }
  ]
}
```

## Classification Dimensions

### Code Sensitivity Level (0-3)
- **0**: Not sensitive (general docs, external content)
- **1**: Low sensitivity (broad concepts, no implementation details)
- **2**: Medium sensitivity (specific components, modules, patterns)
- **3**: High sensitivity (function names, signatures, specific code structure)

### Staleness Risk (1-3)
- **1**: Low risk - Stable concepts that rarely change
- **2**: Medium risk - May become outdated as features evolve
- **3**: High risk - Likely to become outdated quickly

### Technical Patterns
- API/Routing, Database/Schema, Background/Jobs, Authentication/Authorization
- Frontend/UI, Infrastructure/DevOps, Testing/QA, Configuration/Environment
- Data/Analytics, Integration/External, Performance/Optimization
- Security/Compliance, Documentation/Process

### Document Types
- API Reference (Beginner/Advanced)
- Setup Guide (Quick Start/Comprehensive)
- Tutorial (Step-by-Step/Interactive)
- Architecture (Overview/Deep-Dive)
- Process Documentation, Troubleshooting Guide
- Contributing Guidelines, Reference Documentation
- Policy/Compliance, Release Notes, FAQ/Help

## Requirements

- GitHub repository with documentation files
- GitHub Copilot access for AI classification
- Appropriate permissions for the GitHub token

## Next Steps

Use this action in combination with the [Documentation Drift Detective](../docs-drift-detective) action to automatically detect when documentation may be outdated based on code changes.
