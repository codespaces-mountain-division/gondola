# GitHub Actions Setup for Documentation Drift Detection

This repository now has GitHub Actions configured to automatically detect when documentation might be outdated due to code changes.

## 🚀 Quick Start Guide

### What's Been Created

I've added these files to your repository:

- `.github/workflows/documentation-management.yml` - Main workflow file
- `.github/actions/docs-knowledge-base-updater/` - Action for classifying docs  
- `.github/actions/docs-drift-detective/` - Action for detecting drift

## Manual Steps Required (Do These on GitHub.com)

### 1. Configure Repository Permissions

1. Go to your repository on **GitHub.com**
2. Navigate to **Settings → Actions → General**
3. Under "Workflow permissions", select:
   - ✅ **"Read and write permissions"**
   - ✅ **"Allow GitHub Actions to create and approve pull requests"**
4. Click **Save**

### 2. Verify GitHub Copilot Access

The actions use GitHub Copilot for AI analysis. Ensure:

- Your account has GitHub Copilot access (Individual/Business/Enterprise)
- The repository can access Copilot through your GITHUB_TOKEN

## What You Can Do Now

### Commit the New Files

```bash
git add .github/
git commit -m "Add GitHub Actions for documentation drift detection"
git push origin main
```

### Test the Setup

1. **First push** (with documentation changes) will create the knowledge base
2. **Create a test PR** to see drift detection in action

## How It Works

### Two-Stage Process

**Stage 1: Knowledge Base Creation**
- Triggers when documentation files are pushed to main/master
- Classifies all documentation files by code sensitivity
- Creates `.github/docs-knowledge-base.json`

**Stage 2: Drift Detection**  
- Triggers on pull requests
- Analyzes code changes against the knowledge base
- Posts comments highlighting docs that might need updates

### What Files Are Analyzed

- `**/*.md` - All Markdown files
- `**/README*` - README files
- `**/CHANGELOG*` - Changelog files  
- `**/CONTRIBUTING*` - Contributing guides

## Expected Workflow

### First Run (Knowledge Base Creation)

```text
✅ Documentation files classified
📄 12 files analyzed  
📊 Knowledge base updated at .github/docs-knowledge-base.json
```

### Pull Request Analysis

The bot posts comments like:

```text
## 📚 Documentation Drift Analysis

🔍 Analysis Summary:
- 3 documentation files analyzed
- 2 potential updates identified  
- 1 high-priority, 1 medium-priority

### 🚨 High Priority Updates

#### 📄 README.md
**Installation section, lines 25-35**
- References old setup commands that may have changed
- Suggestion: Verify installation steps match current codebase
```

## Configuration Options

You can customize the workflow by editing `.github/workflows/documentation-management.yml`:

### Sensitivity Threshold
- **Level 0:** General documentation (minimal code coupling)
- **Level 1:** Broad concepts documentation
- **Level 2:** Component-specific documentation ⭐ (current default)
- **Level 3:** Highly code-sensitive documentation

### Other Settings
- Maximum documents analyzed per PR (default: 20)
- File patterns to include/exclude
- Comment posting behavior

## Troubleshooting

### Common Issues

**"No knowledge base found"**
- Push documentation changes to main/master first to create the knowledge base

**Copilot API errors**  
- Verify your repository has GitHub Copilot access
- Check GITHUB_TOKEN permissions in repository settings

**Workflow not triggering**
- Ensure workflow file is in `.github/workflows/`
- Check file patterns match your documentation files

**Permission errors**
- Verify "Read and write permissions" is enabled (see step 1 above)

### Getting Help

- Check the **Actions** tab in your repository for detailed logs
- Workflow runs show exactly what files were processed
- Error messages provide specific troubleshooting steps

## Next Steps

1. ✅ **Commit the files** (see commands above)
2. ⚙️ **Configure repository settings** (see manual steps above)
3. 🧪 **Create a test PR** to see drift detection in action
4. 🎯 **Customize the workflow** based on your needs

---

**Questions?** Check the workflow logs in the Actions tab of your repository for detailed information about what's happening.
