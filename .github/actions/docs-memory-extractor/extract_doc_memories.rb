#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'
require 'base64'
require 'optparse'
require 'fileutils'
require 'pathname'
require 'time'
require 'digest'

class DocumentationMemoryExtractor
  def initialize(options = {})
    @github_token = ENV['GITHUB_TOKEN'] || options[:github_token]
    @copilot_token = ENV['COPILOT_TOKEN'] || options[:copilot_token]
    
    # Debug token assignment
    puts "🔍 Debug: ENV['GITHUB_TOKEN'] present: #{!ENV['GITHUB_TOKEN'].nil?}"
    puts "🔍 Debug: ENV['GITHUB_TOKEN'] length: #{ENV['GITHUB_TOKEN']&.length || 'nil'}"
    puts "🔍 Debug: ENV['COPILOT_TOKEN'] present: #{!ENV['COPILOT_TOKEN'].nil?}"
    puts "🔍 Debug: ENV['COPILOT_TOKEN'] length: #{ENV['COPILOT_TOKEN']&.length || 'nil'}"
    puts "🔍 Debug: @github_token length: #{@github_token&.length || 'nil'}"
    puts "🔍 Debug: @copilot_token length: #{@copilot_token&.length || 'nil'}"
    
    # Use GitHub token for Copilot API as fallback only if no separate Copilot token
    if !@copilot_token && @github_token
      @copilot_token = @github_token
      puts "🔍 Debug: Using GitHub token as Copilot token fallback"
    end
    
    puts "🔍 Debug: Final @copilot_token length: #{@copilot_token&.length || 'nil'}"
    
    @repository = options[:repository]
    @commit_sha = options[:commit_sha]
    @docs_patterns = parse_patterns(options[:docs_patterns] || "**/*.md\n**/*.markdown")
    @exclude_patterns = parse_patterns(options[:exclude_patterns] || "node_modules/**\n.git/**")
    @operation = options[:operation] || 'extract'
    
    validate_inputs!
  end

  def extract_and_store_memories
    puts "🧠 Extracting memories for documentation changes in commit #{@commit_sha}..."
    
    # Get the commit details and changed files
    changed_docs = discover_changed_documentation_files
    
    if changed_docs.empty?
      puts "ℹ️  No documentation files changed in this commit"
      return
    end

    puts "📄 Found #{changed_docs.length} changed documentation files"
    changed_docs.each { |file| puts "   - #{file[:path]}" }
    
    # Extract memories from each changed documentation file
    puts "🤖 Extracting memories using AI..."
    memories_by_file = extract_memories_from_files(changed_docs)
    
    if memories_by_file.empty?
      puts "⚠️  No memories extracted from documentation files"
      return
    end
    
    # Format the memories note
    note_content = format_memories_note(memories_by_file)
    
    # Display extracted memories before storing
    puts "🧠 Extracted memories:"
    puts "=" * 50
    puts note_content
    puts "=" * 50
    
    # Store as git note
    puts "📝 Storing memories as git note..."
    store_git_note(note_content)
    
    output_summary(memories_by_file)
  end

  def get_git_note(commit_sha = nil, namespace = "documentation/memories")
    sha = commit_sha || @commit_sha
    
    puts "🔍 Looking for git note for commit #{sha} in namespace #{namespace}"
    
    # Use git notes show command
    git_cmd = "git notes --ref=#{namespace} show #{sha} 2>&1"
    puts "🔍 Debug: Running git command: #{git_cmd}"
    
    result = `#{git_cmd}`
    exit_code = $?.exitstatus
    
    if exit_code == 0
      puts "✅ Found git note for commit #{sha}"
      puts "📝 Note content:"
      puts result
      return result
    else
      puts "⚠️  No git note found for commit #{sha} in namespace #{namespace}"
      puts "🔍 Git output: #{result.strip}" if result && !result.strip.empty?
      return nil
    end
  end

  def has_git_note?(commit_sha = nil, namespace = "documentation/memories")
    sha = commit_sha || @commit_sha
    
    # Check if a git note exists for the commit
    git_cmd = "git notes --ref=#{namespace} show #{sha} 2>/dev/null"
    result = `#{git_cmd}`
    exit_code = $?.exitstatus
    
    if exit_code == 0
      puts "✅ Git note exists for commit #{sha}"
      return true
    else
      puts "❌ No git note found for commit #{sha}"
      return false
    end
  end

  def list_git_notes(namespace = "documentation/memories")
    puts "📋 Listing all git notes in namespace: #{namespace}"
    
    # List all notes in the namespace
    git_cmd = "git notes --ref=#{namespace} list 2>&1"
    result = `#{git_cmd}`
    exit_code = $?.exitstatus
    
    if exit_code == 0 && !result.strip.empty?
      puts "✅ Found git notes:"
      result.lines.each_with_index do |line, index|
        note_sha, commit_sha = line.strip.split(' ')
        puts "  #{index + 1}. Commit: #{commit_sha} (Note: #{note_sha})"
      end
      return result.lines.map(&:strip)
    else
      puts "ℹ️  No git notes found in namespace #{namespace}"
      return []
    end
  end

  private

  def validate_inputs!
    raise "GitHub token is required" unless @github_token
    raise "Repository is required" unless @repository
    
    # Only require commit SHA for operations that need it
    if @operation == 'extract' || @operation == 'get_note' || @operation == 'check_note'
      raise "Commit SHA is required" unless @commit_sha
    end
    
    # Only require Copilot token for extraction operations
    if @operation == 'extract'
      raise "Copilot token is required" unless @copilot_token
    end
    
    # Additional token validation
    if @copilot_token&.include?("\n") || @copilot_token&.include?(" ")
      puts "⚠️  Warning: Copilot token contains whitespace or newlines"
      @copilot_token = @copilot_token.strip
    end
    
    puts "🔍 Token validation: #{@copilot_token&.length || 0} characters"
  end

  def parse_patterns(patterns_string)
    return [] unless patterns_string
    patterns_string.split("\n").map(&:strip).reject(&:empty?)
  end

  def discover_changed_documentation_files
    # Get the commit details
    commit_info = github_api_request("GET", "/repos/#{@repository}/commits/#{@commit_sha}")
    return [] unless commit_info

    changed_files = commit_info['files'] || []
    documentation_files = []

    changed_files.each do |file|
      file_path = file['filename']
      
      # Check if file matches documentation patterns
      matches_docs = @docs_patterns.any? { |pattern| 
        File.fnmatch(pattern, file_path, File::FNM_PATHNAME) 
      }
      
      # Check if file matches exclude patterns
      excluded = @exclude_patterns.any? { |exclude_pattern| 
        File.fnmatch(exclude_pattern, file_path, File::FNM_PATHNAME) 
      }
      
      # Only include files that match docs patterns and aren't excluded
      if matches_docs && !excluded && file['status'] != 'removed'
        puts "✅ Including changed documentation file: #{file_path}"
        documentation_files << {
          path: file_path,
          status: file['status'], # added, modified, etc.
          additions: file['additions'],
          deletions: file['deletions']
        }
      elsif matches_docs && excluded
        puts "🚫 Excluding #{file_path} (matched exclude pattern)"
      end
    end

    documentation_files
  end

  def extract_memories_from_files(changed_docs)
    memories_by_file = {}
    
    # Process files in batches to manage API limits
    changed_docs.each_slice(3) do |batch|
      batch_memories = extract_memories_batch(batch)
      memories_by_file.merge!(batch_memories)
      
      # Be respectful of API limits
      sleep(1) if changed_docs.length > 3
    end
    
    memories_by_file
  end

  def extract_memories_batch(files)
    # Fetch content for each file
    files_with_content = fetch_files_content(files)
    
    # Filter out files we couldn't fetch
    valid_files = files_with_content.select { |f| f[:content] }
    
    return {} if valid_files.empty?
    
    # Extract memories using AI
    prompt = build_memory_extraction_prompt(valid_files)
    response = copilot_api_request(prompt)
    
    return {} unless response
    
    parse_memory_response(response, valid_files)
  end

  def fetch_files_content(files)
    files.map do |file|
      content = fetch_file_content(file[:path])
      file.merge(content: content)
    end
  end

  def fetch_file_content(file_path)
    response = github_api_request("GET", "/repos/#{@repository}/contents/#{file_path}?ref=#{@commit_sha}")
    return nil unless response && response['content']
    
    content = Base64.decode64(response['content'])
    content.force_encoding('UTF-8')
    unless content.valid_encoding?
      content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    content
  rescue => e
    puts "⚠️  Error fetching #{file_path}: #{e.message}"
    nil
  end

  def build_memory_extraction_prompt(files_with_content)
    files_json = files_with_content.map.with_index do |file, index|
      {
        document_number: index + 1,
        file_path: file[:path],
        file_name: File.basename(file[:path]),
        content: file[:content]
      }
    end

    <<~PROMPT
      You are a documentation analysis expert specializing in extracting factual assumptions and statements from technical documentation. Your task is to distill documentation into discrete "memories" - factual statements that capture the essential knowledge, assumptions, and technical facts contained within the documentation.

      ## EXTRACTION GUIDELINES

      **What to extract as memories:**
      1. **Factual technical statements** - APIs that exist, components that are available, processes that occur
      2. **System assumptions** - What entities, services, or infrastructure is presumed to exist
      3. **Configuration facts** - Specific settings, values, paths, or requirements that are stated
      4. **Dependency relationships** - What depends on what, integration points, required connections
      5. **Behavioral statements** - How things work, what happens when actions are taken
      6. **Implicit technical requirements** - Unstated but necessary prerequisites or conditions

      **Memory quality standards:**
      - **Context-aware**: Include relevant system/project context when it helps clarify the statement
      - **Technically precise**: Use specific terms rather than vague descriptions
      - **Assumption-explicit**: Call out implicit dependencies and prerequisites
      - **Consolidatable**: Combine related facts when they strengthen each other
      - **Succinct**: Each memory should be one clear, complete factual statement

      **Example transformation:**
      Original: "You can install the 1Password CLI in your Codespace to automatically load the necessary secrets from the CAPI 1Password vault when the server starts. This eliminates the need to set or update secrets manually."
      
      Extracted memories:
      - "A CAPI 1Password vault exists and contains necessary secrets for server operation"
      - "The server startup process includes logic to invoke the 1Password CLI for secret loading"
      - "1Password CLI is compatible with Codespace environments"
      - "Manual secret management is the default approach without 1Password CLI integration"

      **Prioritization:**
      1. Technical facts over procedural steps
      2. System architecture insights over user instructions
      3. Dependencies and integrations over standalone features
      4. Implicit assumptions over explicit statements (when the implicit adds value)

      ## DOCUMENTS TO ANALYZE

      #{JSON.pretty_generate(files_json)}

      ## RESPONSE FORMAT

      Respond with a JSON object where each key is the file path and each value is an array of memory strings. Each memory should be a standalone factual statement that captures essential knowledge from that document.

      ```json
      {
        "docs/api.md": [
          "Authentication endpoints require Bearer token format in Authorization header",
          "Rate limiting applies at 100 requests per minute per API key",
          "Database connection pooling is configured for API backend services"
        ],
        "README.md": [
          "Application requires Node.js version 18 or higher",
          "PostgreSQL database must be running on port 5432 for local development"
        ]
      }
      ```

      Focus on extracting memories that would be valuable for understanding system architecture, dependencies, and technical requirements. Avoid procedural steps unless they reveal important technical facts about the system.
    PROMPT
  end

  def parse_memory_response(response, files)
    begin
      # Handle JSON wrapped in markdown code blocks
      json_content = response
      if response.include?('```json')
        match = response.match(/```json\s*(.*?)\s*```/m)
        json_content = match[1].strip if match
      elsif response.include?('```')
        match = response.match(/```\s*(.*?)\s*```/m)
        json_content = match[1].strip if match
      end
      
      memories_data = JSON.parse(json_content || response)
      
      # Validate that we have memories for the files we expected
      validated_memories = {}
      files.each do |file|
        file_path = file[:path]
        if memories_data[file_path] && memories_data[file_path].is_a?(Array)
          validated_memories[file_path] = memories_data[file_path]
          puts "✅ Extracted #{memories_data[file_path].length} memories from #{file_path}"
        else
          puts "⚠️  No memories extracted for #{file_path}"
        end
      end
      
      validated_memories
    rescue JSON::ParserError => e
      puts "⚠️  Error parsing memory response: #{e.message}"
      puts "📋 Raw response preview: #{response[0..200]}#{response.length > 200 ? '...' : ''}"
      {}
    end
  end

  def format_memories_note(memories_by_file)
    note_lines = []
    
    memories_by_file.each do |file_path, memories|
      note_lines << "# #{file_path}"
      memories.each do |memory|
        note_lines << memory
      end
      note_lines << "" # Empty line between files
    end
    
    # Remove trailing empty line
    note_lines.pop if note_lines.last == ""
    
    note_lines.join("\n")
  end

  def store_git_note(note_content)
    # Store as actual git notes using git commands
    namespace = "documentation/memories"
    
    puts "📝 Creating git note in namespace: #{namespace}"
    puts "🔍 Debug: Target commit SHA: #{@commit_sha}"
    puts "🔍 Debug: Note content length: #{note_content.length} characters"
    
    # Configure git identity for GitHub Actions environment
    configure_git_identity
    
    # Fetch remote notes FIRST to avoid conflicts
    puts "🔄 Fetching remote git notes before creating new note..."
    fetch_cmd = "git fetch origin +refs/notes/#{namespace}:refs/notes/#{namespace} 2>&1"
    puts "🔍 Debug: Fetching notes: #{fetch_cmd}"
    fetch_result = `#{fetch_cmd}`
    fetch_exit_code = $?.exitstatus
    puts "🔍 Debug: Fetch exit code: #{fetch_exit_code}"
    puts "🔍 Debug: Fetch result: #{fetch_result.strip}" unless fetch_result.strip.empty?
    
    if fetch_exit_code == 0
      puts "✅ Successfully fetched remote git notes"
    else
      puts "ℹ️  No remote git notes to fetch (or fetch failed): #{fetch_result.strip}"
      # This is not necessarily an error - might be the first note
    end
    
    # Write note content to a temporary file
    temp_file = "/tmp/git_note_#{@commit_sha}"
    File.write(temp_file, note_content)
    puts "🔍 Debug: Temp file created at: #{temp_file}"
    puts "🔍 Debug: Temp file size: #{File.size(temp_file)} bytes"
    
    # Verify the commit exists
    commit_check_cmd = "git cat-file -e #{@commit_sha} 2>&1"
    commit_check_result = `#{commit_check_cmd}`
    commit_check_exit = $?.exitstatus
    puts "🔍 Debug: Commit exists check: #{commit_check_exit == 0 ? 'SUCCESS' : 'FAILED'}"
    if commit_check_exit != 0
      puts "❌ Commit #{@commit_sha} does not exist: #{commit_check_result}"
      File.delete(temp_file) if File.exist?(temp_file)
      return false
    end
    
    # Check if a note already exists for this commit
    existing_note_cmd = "git notes --ref=#{namespace} show #{@commit_sha} 2>/dev/null"
    existing_note_result = `#{existing_note_cmd}`
    note_exists = $?.exitstatus == 0
    puts "🔍 Debug: Note already exists: #{note_exists}"
    
    # Use appropriate git notes command
    if note_exists
      puts "ℹ️  Note already exists for commit, updating..."
      git_cmd = "git notes --ref=#{namespace} add -f -F #{temp_file} #{@commit_sha} 2>&1"
    else
      puts "📝 Creating new note..."
      git_cmd = "git notes --ref=#{namespace} add -F #{temp_file} #{@commit_sha} 2>&1"
    end
    
    puts "🔍 Debug: Running git command: #{git_cmd}"
    
    result = `#{git_cmd}`
    exit_code = $?.exitstatus
    puts "🔍 Debug: Git notes add result: #{result.strip}" unless result.strip.empty?
    puts "🔍 Debug: Git notes add exit code: #{exit_code}"
    
    # Clean up temp file
    File.delete(temp_file) if File.exist?(temp_file)
    
    if exit_code == 0
      puts "✅ Successfully stored git note for commit #{@commit_sha}"
      puts "📝 Note stored in namespace: #{namespace}"
      puts "🔗 Retrieve via: git notes --ref=#{namespace} show #{@commit_sha}"
      
      # Immediately verify the note was created
      verify_cmd = "git notes --ref=#{namespace} show #{@commit_sha} 2>&1"
      puts "🔍 Debug: Verifying note creation: #{verify_cmd}"
      verify_result = `#{verify_cmd}`
      verify_exit = $?.exitstatus
      puts "🔍 Debug: Verification exit code: #{verify_exit}"
      if verify_exit == 0
        puts "✅ Note verification successful - note exists locally"
        puts "🔍 Debug: Note content preview: #{verify_result[0..100]}..."
      else
        puts "❌ Note verification failed: #{verify_result.strip}"
        return false
      end
      
      # List all notes to see what's actually stored
      list_cmd = "git notes --ref=#{namespace} list 2>&1"
      puts "🔍 Debug: Listing all notes: #{list_cmd}"
      list_result = `#{list_cmd}`
      list_exit = $?.exitstatus
      puts "🔍 Debug: List notes exit code: #{list_exit}"
      puts "🔍 Debug: All notes in namespace:"
      if list_exit == 0 && !list_result.strip.empty?
        list_result.lines.each { |line| puts "   #{line.strip}" }
      else
        puts "   No notes found or error: #{list_result.strip}"
      end
      
      # Now push the notes to remote
      push_cmd = "git push origin refs/notes/#{namespace} 2>&1"
      puts "🔍 Debug: Pushing notes: #{push_cmd}"
      push_result = `#{push_cmd}`
      push_exit_code = $?.exitstatus
      puts "🔍 Debug: Push exit code: #{push_exit_code}"
      puts "🔍 Debug: Push result: #{push_result.strip}" unless push_result.strip.empty?
      
      if push_exit_code == 0
        puts "✅ Successfully pushed git notes to remote"
      else
        puts "⚠️  Failed to push git notes to remote: #{push_result}"
        
        # If push failed due to non-fast-forward, try force push
        if push_result.include?("rejected") && push_result.include?("fetch first")
          puts "🔄 Attempting force push to resolve conflicts..."
          force_push_cmd = "git push --force origin refs/notes/#{namespace} 2>&1"
          puts "🔍 Debug: Force pushing notes: #{force_push_cmd}"
          force_push_result = `#{force_push_cmd}`
          force_push_exit_code = $?.exitstatus
          puts "🔍 Debug: Force push exit code: #{force_push_exit_code}"
          puts "🔍 Debug: Force push result: #{force_push_result.strip}" unless force_push_result.strip.empty?
          
          if force_push_exit_code == 0
            puts "✅ Successfully force-pushed git notes to remote"
          else
            puts "⚠️  Force push also failed: #{force_push_result}"
            puts "ℹ️  Note is stored locally but may not be visible in GitHub UI"
          end
        else
          puts "ℹ️  Note is stored locally but may not be visible in GitHub UI"
        end
      end
    else
      puts "⚠️  Failed to store git note: #{result}"
      return false
    end
    
    true
  end

  def configure_git_identity
    # Check if git identity is already configured (local repo only)
    user_name = `git config --local user.name 2>/dev/null`.strip
    user_email = `git config --local user.email 2>/dev/null`.strip
    
    if user_name.empty? || user_email.empty?
      puts "🔧 Configuring git identity for GitHub Actions..."
      
      # Use GitHub Actions bot identity
      name = "github-actions[bot]"
      email = "github-actions[bot]@users.noreply.github.com"
      
      # Set local git configuration (only for this repo)
      `git config --local user.name "#{name}"`
      `git config --local user.email "#{email}"`
      
      puts "✅ Git identity configured: #{name} <#{email}>"
    else
      puts "✅ Git identity already configured: #{user_name} <#{user_email}>"
    end
  end

  def output_summary(memories_by_file)
    total_memories = memories_by_file.values.flatten.length
    
    puts "\n🧠 Memory Extraction Summary:"
    puts "   Files processed: #{memories_by_file.keys.length}"
    puts "   Total memories extracted: #{total_memories}"
    puts "   Average memories per file: #{(total_memories.to_f / memories_by_file.keys.length).round(1)}"
    
    memories_by_file.each do |file_path, memories|
      puts "   #{file_path}: #{memories.length} memories"
    end
    
    # Set GitHub Actions outputs
    if ENV['GITHUB_OUTPUT']
      File.open(ENV['GITHUB_OUTPUT'], 'a') do |f|
        f.puts "memories-extracted=#{total_memories}"
        f.puts "files-processed=#{memories_by_file.keys.length}"
        f.puts "commit-sha=#{@commit_sha}"
      end
    else
      # Fallback for older versions
      puts "::set-output name=memories-extracted::#{total_memories}"
      puts "::set-output name=files-processed::#{memories_by_file.keys.length}"
      puts "::set-output name=commit-sha::#{@commit_sha}"
    end
  end

  def github_api_request(method, path, body = nil)
    uri = URI("https://api.github.com#{path}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = case method
    when "GET"
      Net::HTTP::Get.new(uri)
    when "POST"
      Net::HTTP::Post.new(uri)
    when "PUT"
      Net::HTTP::Put.new(uri)
    else
      raise "Unsupported method: #{method}"
    end
    
    request['Authorization'] = "token #{@github_token}"
    request['Accept'] = 'application/vnd.github.v3+json'
    request['User-Agent'] = 'GitHub-Action-Docs-Memory-Extractor'
    
    if body
      request['Content-Type'] = 'application/json'
      request.body = body.to_json
    end
    
    response = http.request(request)
    
    if response.code.to_i >= 400
      puts "⚠️  GitHub API error: #{response.code} - #{response.body}"
      return nil
    end
    
    JSON.parse(response.body)
  rescue => e
    puts "⚠️  GitHub API request failed: #{e.message}"
    nil
  end

  def copilot_api_request(prompt)
    uri = URI('https://api.githubcopilot.com/chat/completions')
    
    # Debug token format
    puts "🔍 Debug: Token length: #{@copilot_token&.length || 'nil'}"
    
    # Clean the token of any whitespace
    clean_token = @copilot_token&.strip
    puts "🔍 Debug: Cleaned token length: #{clean_token&.length || 'nil'}"
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{clean_token}"
    request['Content-Type'] = 'application/json'
    request['Copilot-Integration-Id'] = 'playground-dev'
    
    request.body = {
      model: 'gpt-4',
      messages: [
        {
          role: 'user',
          content: prompt
        }
      ],
      max_tokens: 4000,
      temperature: 0.1
    }.to_json
    
    response = http.request(request)
    
    puts "🔍 Debug: Response code: #{response.code}"
    puts "🔍 Debug: Response headers: #{response.to_hash}"
    
    if response.code.to_i >= 400
      puts "⚠️  Copilot API error: #{response.code} - #{response.body}"
      puts "🔍 Debug: Full response body: #{response.body[0..500]}"
      return nil
    end
    
    data = JSON.parse(response.body)
    data.dig('choices', 0, 'message', 'content')
  rescue => e
    puts "⚠️  Copilot API request failed: #{e.message}"
    nil
  end
end

# Command line interface
if __FILE__ == $0
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    
    opts.on("--repository REPO", "Repository to analyze (org/name)") do |repo|
      options[:repository] = repo
    end
    
    opts.on("--commit-sha SHA", "Commit SHA to extract memories for") do |sha|
      options[:commit_sha] = sha
    end
    
    opts.on("--docs-patterns PATTERNS", "Newline-separated file patterns to include") do |patterns|
      options[:docs_patterns] = patterns
    end
    
    opts.on("--exclude-patterns PATTERNS", "Newline-separated file patterns to exclude") do |patterns|
      options[:exclude_patterns] = patterns
    end
    
    opts.on("--get-note", "Retrieve and display git note for the specified commit") do
      options[:get_note] = true
    end
    
    opts.on("--check-note", "Check if a git note exists for the specified commit") do
      options[:check_note] = true
    end
    
    opts.on("--list-notes", "List all git notes in the documentation/memories namespace") do
      options[:list_notes] = true
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  begin
    if options[:get_note]
      options[:operation] = 'get_note'
      extractor = DocumentationMemoryExtractor.new(options)
      extractor.get_git_note
    elsif options[:check_note]
      options[:operation] = 'check_note'
      extractor = DocumentationMemoryExtractor.new(options)
      if extractor.has_git_note?
        puts "✅ Git note exists for commit #{options[:commit_sha] || 'HEAD'}"
        exit 0
      else
        puts "❌ No git note found for commit #{options[:commit_sha] || 'HEAD'}"
        exit 1
      end
    elsif options[:list_notes]
      options[:operation] = 'list_notes'
      extractor = DocumentationMemoryExtractor.new(options)
      extractor.list_git_notes
    else
      options[:operation] = 'extract'
      extractor = DocumentationMemoryExtractor.new(options)
      extractor.extract_and_store_memories
    end
  rescue => e
    puts "❌ Error: #{e.message}"
    exit 1
  end
end
