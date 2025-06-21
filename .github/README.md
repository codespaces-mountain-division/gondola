# Documentation Drift Detection Actions

A complete GitHub Actions workflow that automatically detects when documentation might be outdated due to code changes, using AI-powered classification and drift analysis.

## 🎯 What This Does

This workflow provides **automated documentation maintenance** by:

1. **📊 Classifying Documentation** - AI analyzes your docs by code sensitivity, staleness risk, and technical patterns
2. **🕵️ Detecting Drift** - When code changes in PRs, AI identifies docs that might need updates
3. **💬 Providing Feedback** - Posts specific, actionable suggestions as PR comments
4. **🔄 Staying Current** - Automatically maintains a knowledge base as your docs evolve

## 🚀 Quick Start

### Prerequisites
- **GitHub Copilot access** for your repository
- **Repository write permissions** for GitHub Actions

### 1. Add to Your Repository

Copy these files to your repository:
```
.github/
├── workflows/
│   └── documentation-management.yml      # Main workflow
└── actions/
    ├── docs-knowledge-base-updater/       # Classification action
    │   ├── action.yml
    │   ├── classify_repository_docs.rb
    │   └── README.md
    └── docs-drift-detective/              # Drift detection action
        ├── action.yml
        ├── analyze_docs_drift.rb
        └── README.md
```

### 2. Configure Repository Settings (GitHub.com)

1. Go to your repository → **Settings → Actions → General**
2. Under "Workflow permissions":
   - ✅ Select **"Read and write permissions"**
   - ✅ Check **"Allow GitHub Actions to create and approve pull requests"**
3. Click **Save**

### 3. Set Up Copilot Token (If Needed)

If you get "Authorization header is badly formatted" errors:

1. **Create Personal Access Token:**
   - Go to **GitHub.com → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
   - Create token with **"GitHub Copilot Chat"** permissions for your repository

2. **Add Repository Secret:**
   - Go to your repository → **Settings → Secrets and variables → Actions**
   - Click **"New repository secret"**
   - Name: `COPILOT_TOKEN`
   - Value: Your personal access token

### 4. Test the Setup

```bash
git add .github/
git commit -m "Add documentation drift detection workflow"
git push origin main
```

## Files

- `workflows/documentation-management.yml` - Main workflow
- `actions/docs-knowledge-base-updater/` - Classification action
- `actions/docs-drift-detective/` - Drift detection action
- `SETUP_GUIDE.md` - Complete setup instructions

## 📈 How It Works

### Stage 1: Knowledge Base Creation
**Triggers:** Push to main/master with documentation changes

1. **Discovers** all documentation files matching patterns
2. **Classifies** each file using AI across 4 dimensions:
   - **Code Sensitivity** (0-3): How tightly coupled to code
   - **Staleness Risk** (1-3): Likelihood of becoming outdated  
   - **Technical Patterns**: Which tech areas are covered
   - **Document Type**: Purpose and audience
3. **Generates** `.github/docs-knowledge-base.json` with classification data

### Stage 2: Drift Detection  
**Triggers:** Pull request opened/updated

1. **Loads** existing knowledge base
2. **Analyzes** PR code changes
3. **Identifies** docs likely to be affected using AI
4. **Posts** specific update suggestions as PR comments

## 📄 What Gets Analyzed

### File Patterns (Configurable)
- `**/*.md` - All Markdown files
- `**/*.markdown` - Markdown files  
- `**/README*` - README files
- `**/CHANGELOG*` - Changelog files
- `**/CONTRIBUTING*` - Contributing guides

### Excluded by Default
- `node_modules/**`
- `.git/**`
- `vendor/**`
- `.github/workflows/**`
- `tmp/**`
- `log/**`

## 🎛️ Configuration Options

### Sensitivity Levels
Control which docs get analyzed in PRs:
- **Level 0:** General documentation (minimal code coupling)
- **Level 1:** Broad concepts documentation
- **Level 2:** Component-specific documentation ⭐ **(recommended default)**
- **Level 3:** Highly code-sensitive documentation

### Workflow Customization

Edit `.github/workflows/documentation-management.yml` to customize:

```yaml
# Change file patterns
docs-patterns: |
  **/*.md
  **/*.rst
  docs/**/*.txt

# Adjust sensitivity threshold (0-3)
sensitivity-threshold: '2'

# Limit analysis scope
max-docs-to-analyze: '20'

# Change comment behavior
comment-mode: 'review'  # 'comment', 'review', or 'annotation'
```

## 📊 Example Output

### Knowledge Base Creation
```
✅ Documentation files classified
📄 12 files analyzed
📊 Knowledge base updated at .github/docs-knowledge-base.json
```

### Drift Detection Comments
```markdown
## 📚 Documentation Drift Analysis

🔍 **Analysis Summary:**
- 3 documentation files analyzed
- 2 potential updates identified
- 1 high-priority, 1 medium-priority

### 🚨 High Priority Updates

#### 📄 `docs/api.md`
**Authentication section, lines 45-60**
- References old AuthController methods that may have changed
- *Suggestion: Verify authentication flow and update examples*

#### 📄 `README.md`  
**Installation section, lines 25-35**
- Setup commands may not match current configuration
- *Suggestion: Test installation steps with latest codebase*
```

## 🛠️ Troubleshooting

### Common Issues

**❌ "No knowledge base found"**
- **Solution:** Push documentation changes to main/master first to create the knowledge base

**❌ "Authorization header is badly formatted"**  
- **Solution:** Set up COPILOT_TOKEN secret (see setup instructions above)

**❌ Workflow not triggering**
- **Solution:** Check that file patterns match your documentation files
- **Solution:** Ensure workflow file is in `.github/workflows/` directory

**❌ Permission errors**
- **Solution:** Enable "Read and write permissions" in repository Actions settings

**❌ Found 0 files**
- **Solution:** Check docs-patterns in workflow match your file structure
- **Solution:** Verify exclude-patterns aren't too broad

### Getting Help

- **Check workflow logs** in the Actions tab for detailed information
- **Review file patterns** in the workflow configuration
- **Test locally** by running the Ruby scripts directly

## 🔧 Advanced Usage

### Custom File Patterns

```yaml
docs-patterns: |
  docs/**/*.md
  wiki/**/*.markdown
  *.rst
  README*
  CHANGELOG*
  
exclude-patterns: |
  docs/generated/**
  **/node_modules/**
  vendor/**
```

### Multiple Repositories

The actions are designed to be **repository-agnostic**. Simply copy the `.github/` directory to any repository and it will automatically discover and classify that repository's documentation.

### Integration with Existing Workflows

```yaml
# Add to existing PR workflow
jobs:
  test:
    # ... your existing tests
  
  docs-drift-check:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/docs-drift-detective
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          copilot-token: ${{ secrets.COPILOT_TOKEN }}
```

## 📁 File Structure

```
.github/
├── workflows/
│   └── documentation-management.yml           # Main workflow
├── actions/
│   ├── docs-knowledge-base-updater/
│   │   ├── action.yml                        # Action definition
│   │   └── classify_repository_docs.rb       # Classification logic
│   └── docs-drift-detective/
│       ├── action.yml                        # Action definition  
│       └── analyze_docs_drift.rb             # Drift detection logic
└── docs-knowledge-base.json                   # Generated knowledge base (after first run)
```

## 🚦 Getting Started Checklist

- [ ] Copy `.github/` directory to your repository
- [ ] Configure repository permissions (Settings → Actions → General)
- [ ] Set up COPILOT_TOKEN secret (if needed)
- [ ] Commit and push the files
- [ ] Make a documentation change to trigger knowledge base creation
- [ ] Create a test PR to see drift detection in action
- [ ] Customize file patterns and sensitivity as needed

## 🎯 What Happens Next

1. **First documentation push** → Knowledge base gets created
2. **Future PRs** → Automatic drift detection with AI-powered suggestions
3. **Documentation updates** → Knowledge base stays current automatically
4. **Continuous improvement** → Better drift detection as the knowledge base grows

---

**Ready to get started?** Copy the files, configure the settings, and push to see AI-powered documentation drift detection in action! 🚀
