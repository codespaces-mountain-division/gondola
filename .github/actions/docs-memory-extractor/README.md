# Documentation Memory Extractor

This GitHub Action extracts factual "memories" from documentation files when they are updated via commits. It uses AI to distill documentation into discrete factual statements and assumptions, then stores them as git notes for future reference.

## What are "memories"?

Memories are factual statements extracted from documentation that capture:

- **Technical facts** - APIs, components, processes that exist
- **System assumptions** - Infrastructure, services, or entities presumed to exist  
- **Configuration details** - Specific settings, paths, requirements
- **Dependencies** - What depends on what, integration points
- **Behavioral statements** - How things work, what happens when actions occur
- **Implicit requirements** - Unstated but necessary prerequisites

## Example

Given this documentation:

```markdown
You can install the 1Password CLI in your Codespace to automatically load the necessary secrets from the CAPI 1Password vault when the server starts. This eliminates the need to set or update secrets manually.
```

The extractor would produce memories like:

- "A CAPI 1Password vault exists and contains necessary secrets for server operation"
- "The server startup process includes logic to invoke the 1Password CLI for secret loading"
- "1Password CLI is compatible with Codespace environments"
- "Manual secret management is the default approach without 1Password CLI integration"

## Usage

### As a GitHub Action

The action automatically triggers when documentation files are changed:

```yaml
- name: Extract Documentation Memories
  uses: ./.github/actions/docs-memory-extractor
  with:
    repository: ${{ github.repository }}
    commit-sha: ${{ github.sha }}
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Manual Execution

You can also run the script directly:

```bash
ruby extract_doc_memories.rb \
  --repository "owner/repo" \
  --commit-sha "abc123" \
  --docs-patterns "**/*.md" \
  --exclude-patterns "node_modules/**"
```

## Configuration

### Inputs

- `repository` - Repository in format `owner/repo` (default: current repository)
- `commit-sha` - Commit SHA to analyze (default: current commit)
- `docs-patterns` - Newline-separated file patterns to include (default: `**/*.md`, `**/*.markdown`)
- `exclude-patterns` - Newline-separated file patterns to exclude (default: `node_modules/**`, `.git/**`)

### Environment Variables

- `GITHUB_TOKEN` - Required for accessing GitHub API
- `COPILOT_TOKEN` - Required for AI analysis (can use GITHUB_TOKEN if it has Copilot access)

### Outputs

- `memories-extracted` - Total number of memories extracted
- `files-processed` - Number of documentation files processed
- `commit-sha` - Commit SHA that was analyzed

## How it Works

1. **Discovery** - Identifies documentation files changed in the specified commit
2. **Content Fetch** - Retrieves the full content of each changed documentation file
3. **AI Analysis** - Uses Copilot API to extract factual memories from the content
4. **Storage** - Stores the memories as a git note attached to the commit

## Memory Storage Format

When multiple documentation files are changed in a single commit, memories are stored in this format:

```text
# docs/api.md
Authentication endpoints require Bearer token format in Authorization header
Rate limiting applies at 100 requests per minute per API key
Database connection pooling is configured for API backend services

# README.md
Application requires Node.js version 18 or higher
PostgreSQL database must be running on port 5432 for local development
```

## Requirements

- Ruby 3.1+
- GitHub token with repository access
- Copilot API access (usually provided by GitHub token)

## Limitations

- Git notes storage currently uses the default notes ref due to GitHub API limitations
- Large documentation files may be truncated to stay within API token limits
- Processing is limited to avoid API rate limiting

## Future Enhancements

- Support for custom git notes namespaces via direct git operations
- Incremental memory extraction based on file diffs
- Memory consolidation across related documentation files
- Integration with existing documentation drift detection
