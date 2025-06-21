#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'
require 'optparse'
require 'base64'

class DocumentationDriftDetective
  def initialize(options = {})
    @github_token = ENV['GITHUB_TOKEN'] || options[:github_token]
    @copilot_token = ENV['COPILOT_TOKEN'] || options[:copilot_token] || @github_token
    @repository = options[:repository]
    @pr_number = options[:pr_number]
    @knowledge_base_path = options[:knowledge_base_path] || '.github/docs-knowledge-base.json'
    @sensitivity_threshold = (options[:sensitivity_threshold] || 2).to_i
    @comment_mode = options[:comment_mode] || 'comment'
    @max_docs = (options[:max_docs] || 20).to_i
    
    validate_inputs!
  end

  def analyze_documentation_drift
    puts "🔍 Analyzing PR ##{@pr_number} for documentation drift..."
    
    # Load knowledge base
    knowledge_base = load_knowledge_base
    return unless knowledge_base
    
    # Get PR diff
    pr_diff = get_pr_diff
    return unless pr_diff
    
    # Identify potentially affected documentation
    affected_docs = identify_affected_documentation(pr_diff, knowledge_base)
    
    if affected_docs.empty?
      puts "✅ No potentially affected documentation found"
      puts "💡 Analysis Summary:"
      puts "   - Knowledge base contains #{knowledge_base[:files].length} documentation files"
      puts "   - #{knowledge_base[:files].count { |f| f[:code_sensitivity_level] >= @sensitivity_threshold }} files met sensitivity threshold (>= #{@sensitivity_threshold})"
      puts "   - AI determined none of these docs are likely affected by the PR changes"
      puts "   - This could mean: changes are isolated, docs are well-maintained, or threshold is too high"
      return post_no_issues_comment
    end
    
    puts "📄 Found #{affected_docs.length} potentially affected documentation files"
    
    # Analyze each affected document
    analysis_results = analyze_affected_docs(affected_docs, pr_diff)
    
    # Post results as PR comment
    post_analysis_results(analysis_results)
    
    output_summary(analysis_results)
  end

  private

  def validate_inputs!
    raise "GitHub token is required" unless @github_token
    raise "Repository is required" unless @repository
    raise "PR number is required" unless @pr_number
    raise "Copilot token is required" unless @copilot_token
  end

  def load_knowledge_base
    unless File.exist?(@knowledge_base_path)
      puts "⚠️  Knowledge base not found at #{@knowledge_base_path}"
      puts "💡 Run the Documentation Knowledge Base Updater action first"
      return nil
    end
    
    begin
      kb = JSON.parse(File.read(@knowledge_base_path), symbolize_names: true)
      puts "📚 Loaded knowledge base:"
      puts "   - Total documented files: #{kb[:files]&.length || 0}"
      puts "   - Generated: #{kb[:metadata]&.[](:generated_at) || 'unknown'}"
      puts "   - Confidence: #{kb[:metadata]&.[](:avg_confidence) || 'unknown'}"
      
      # Show sensitivity distribution
      if kb[:files]&.any?
        sensitivity_counts = kb[:files].group_by { |f| f[:code_sensitivity_level] }.transform_values(&:count)
        puts "   - Sensitivity distribution: #{sensitivity_counts.map { |k,v| "level #{k}: #{v}" }.join(', ')}"
      end
      
      kb
    rescue JSON::ParserError => e
      puts "⚠️  Error parsing knowledge base: #{e.message}"
      nil
    end
  end

  def get_pr_diff
    # Get PR files and their changes
    pr_files = github_api_request("GET", "/repos/#{@repository}/pulls/#{@pr_number}/files")
    return nil unless pr_files
    
    # Filter for code files (not documentation)
    code_files = pr_files.select do |file|
      !file['filename'].match?(/\\.(md|markdown|rst|txt)$/i) &&
      file['status'] != 'removed' &&
      file['changes'] > 0
    end
    
    {
      pr_files: pr_files,
      code_files: code_files,
      total_additions: code_files.sum { |f| f['additions'] },
      total_deletions: code_files.sum { |f| f['deletions'] },
      modified_paths: code_files.map { |f| f['filename'] }
    }
  end

  def identify_affected_documentation(pr_diff, knowledge_base)
    puts "📋 Starting documentation drift analysis..."
    puts "🔍 Sensitivity threshold: #{@sensitivity_threshold} (analyzing docs with code-sensitivity >= #{@sensitivity_threshold})"
    puts "📊 Total files in knowledge base: #{knowledge_base[:files].length}"
    
    # Get docs that might be affected by this PR
    candidate_docs = knowledge_base[:files].select do |doc|
      doc[:code_sensitivity_level] >= @sensitivity_threshold
    end
    
    puts "🎯 Candidate docs meeting sensitivity threshold: #{candidate_docs.length}"
    if candidate_docs.length > 0
      puts "📄 Candidate documentation files:"
      candidate_docs.each do |doc|
        puts "   - #{doc[:path]} (sensitivity: #{doc[:code_sensitivity_level]}, staleness: #{doc[:staleness_risk_level]})"
      end
    end
    
    # If no high-sensitivity docs, return early
    if candidate_docs.empty?
      puts "ℹ️  No documentation files meet the sensitivity threshold of #{@sensitivity_threshold}"
      puts "   Consider lowering the threshold if you expect more files to be analyzed"
      return []
    end
    
    puts "🤖 Using AI to analyze which docs might be affected by PR changes..."
    puts "📝 PR contains #{pr_diff[:code_files].length} code file changes:"
    pr_diff[:code_files].first(10).each do |file|
      puts "   - #{file['filename']} (+#{file['additions']}/-#{file['deletions']})"
    end
    puts "   ... (showing first 10 files)" if pr_diff[:code_files].length > 10
    
    # Use AI to determine which docs are likely affected
    affected_docs = ai_identify_affected_docs(candidate_docs, pr_diff)
    
    puts "🎯 AI identified #{affected_docs.length} potentially affected docs:"
    affected_docs.each do |doc|
      puts "   - #{doc[:path]} (likelihood: #{doc[:analysis_likelihood]}, priority: #{doc[:analysis_priority]})"
      puts "     Reasoning: #{doc[:analysis_reasoning]}" if doc[:analysis_reasoning]
    end
    
    # Limit to max docs to avoid overwhelming
    limited_docs = affected_docs.first(@max_docs)
    if limited_docs.length < affected_docs.length
      puts "⚠️  Limited analysis to top #{@max_docs} docs (configured max-docs limit)"
    end
    
    limited_docs
  end

  def ai_identify_affected_docs(candidate_docs, pr_diff)
    prompt = build_identification_prompt(candidate_docs, pr_diff)
    
    response = copilot_api_request(prompt)
    return [] unless response
    
    parse_identification_response(response, candidate_docs)
  end

  def build_identification_prompt(docs, pr_diff)
    # Summarize the PR changes
    changed_files = pr_diff[:modified_paths].first(20) # Limit for prompt size
    
    # Summarize the docs
    docs_summary = docs.first(30).map do |doc| # Limit for prompt size
      {
        path: doc[:path],
        technical_patterns: doc[:technical_patterns],
        doc_category: doc[:doc_category],
        key_indicators: doc[:key_indicators]
      }
    end

    <<~PROMPT
      You are a documentation drift detection expert. Analyze a pull request and determine which documentation files might need updates based on the code changes.

      ## Pull Request Changes
      **Files modified:** #{changed_files.length} files
      **Key changed files:**
      #{changed_files.map { |f| "- #{f}" }.join("\\n")}
      
      **Change summary:**
      - #{pr_diff[:total_additions]} lines added
      - #{pr_diff[:total_deletions]} lines deleted

      ## Documentation Files to Evaluate
      #{JSON.pretty_generate(docs_summary)}

      ## Task
      For each documentation file, determine if it's likely to be affected by these PR changes. Consider:
      - Technical patterns covered by the doc vs. areas changed in PR
      - File path relationships (e.g., docs about specific modules/components)
      - Documentation category and how it relates to the changes

      Respond with a JSON array of potentially affected documentation:
      ```json
      [
        {
          "path": "docs/api.md",
          "likelihood": "high",
          "reasoning": "Documents API endpoints that may be affected by controller changes",
          "priority": 3
        }
      ]
      ```

      Likelihood: "high", "medium", "low"
      Priority: 1-3 (3 = most important to check)
    PROMPT
  end

  def parse_identification_response(response, candidate_docs)
    begin
      puts "🔍 AI Analysis Response received, parsing results..."
      
      # Handle JSON wrapped in markdown code blocks
      json_content = response
      if response.include?('```json')
        # Extract JSON from markdown code blocks
        match = response.match(/```json\s*(.*?)\s*```/m)
        json_content = match[1].strip if match
        puts "📋 Extracted JSON from markdown code blocks"
      elsif response.include?('```')
        # Extract from generic code blocks
        match = response.match(/```\s*(.*?)\s*```/m)
        json_content = match[1].strip if match
        puts "📋 Extracted JSON from generic code blocks"
      else
        puts "📋 Processing raw JSON response"
      end
      
      identified = JSON.parse(json_content || response)
      puts "✅ Successfully parsed AI response with #{identified.length} document assessments"
      
      # Match back to original docs and filter by likelihood
      affected_docs = []
      skipped_docs = []
      
      identified.each do |result|
        doc = candidate_docs.find { |d| d[:path] == result['path'] }
        unless doc
          puts "⚠️  AI referenced unknown document: #{result['path']}"
          next
        end
        
        if result['likelihood'] == 'low'
          skipped_docs << {
            path: result['path'],
            likelihood: result['likelihood'],
            reasoning: result['reasoning']
          }
          next
        end
        
        affected_docs << doc.merge(
          analysis_likelihood: result['likelihood'],
          analysis_reasoning: result['reasoning'],
          analysis_priority: result['priority'] || 2
        )
      end
      
      # Log filtering results
      puts "📊 AI Analysis Results:"
      puts "   - Total assessments: #{identified.length}"
      puts "   - Flagged as potentially affected: #{affected_docs.length}"
      puts "   - Skipped (low likelihood): #{skipped_docs.length}"
      
      if skipped_docs.any?
        puts "📝 Documents marked as low likelihood:"
        skipped_docs.each do |doc|
          puts "   - #{doc[:path]}: #{doc[:reasoning]}"
        end
      end
      
      # Sort by priority and likelihood
      sorted_docs = affected_docs.sort_by { |doc| [-doc[:analysis_priority], doc[:analysis_likelihood] == 'high' ? 0 : 1] }
      puts "🎯 Final affected docs (sorted by priority): #{sorted_docs.length}"
      
      sorted_docs
    rescue JSON::ParserError => e
      puts "⚠️  Error parsing identification response: #{e.message}"
      puts "📋 Raw response preview: #{response[0..200]}#{response.length > 200 ? '...' : ''}"
      []
    end
  end

  def analyze_affected_docs(affected_docs, pr_diff)
    results = []
    
    affected_docs.each_slice(5) do |doc_batch|
      batch_results = analyze_doc_batch(doc_batch, pr_diff)
      results.concat(batch_results)
      
      # Be respectful of API limits
      sleep(1)
    end
    
    results
  end

  def analyze_doc_batch(docs, pr_diff)
    # Fetch current content of the docs
    docs_with_content = fetch_docs_content(docs)
    
    # Analyze each doc for potential updates needed
    prompt = build_analysis_prompt(docs_with_content, pr_diff)
    
    response = copilot_api_request(prompt)
    return [] unless response
    
    parse_analysis_response(response, docs_with_content)
  end

  def fetch_docs_content(docs)
    docs.map do |doc|
      content = fetch_file_content(doc[:path])
      doc.merge(current_content: content)
    end
  end

  def fetch_file_content(file_path)
    response = github_api_request("GET", "/repos/#{@repository}/contents/#{file_path}")
    return nil unless response && response['content']
    
    content = Base64.decode64(response['content'])
    content.force_encoding('UTF-8')
    unless content.valid_encoding?
      content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    # Return first 4000 chars to stay within API limits
    content[0, 4000]
  rescue => e
    puts "⚠️  Error fetching #{file_path}: #{e.message}"
    nil
  end

  def build_analysis_prompt(docs_with_content, pr_diff)
    changed_files = pr_diff[:modified_paths].first(15)
    
    docs_for_analysis = docs_with_content.map do |doc|
      {
        path: doc[:path],
        doc_category: doc[:doc_category],
        technical_patterns: doc[:technical_patterns],
        analysis_reasoning: doc[:analysis_reasoning],
        content_preview: doc[:current_content]
      }
    end

    <<~PROMPT
      You are a documentation quality expert. Analyze documentation files to identify specific content that may be outdated based on recent code changes.

      ## Code Changes in This PR
      **Modified files:**
      #{changed_files.map { |f| "- #{f}" }.join("\\n")}
      
      ## Documentation Files to Analyze
      #{JSON.pretty_generate(docs_for_analysis)}

      ## Task
      For each documentation file, carefully read the content and identify specific sections, examples, or statements that might be outdated due to the code changes. Focus on:
      
      1. **Code examples** that might reference changed files/functions
      2. **Configuration instructions** that might be affected
      3. **API documentation** that might need updates
      4. **Process descriptions** that might have changed
      5. **File/module references** that might be stale

      For each potential issue, provide:
      - Specific line/section reference
      - What might be outdated
      - Suggested action

      Respond with JSON:
      ```json
      [
        {
          "path": "docs/api.md",
          "issues": [
            {
              "section": "Authentication section, lines 45-60",
              "issue": "References old AuthController methods that may have changed",
              "severity": "high",
              "suggestion": "Verify authentication flow and update examples"
            }
          ],
          "overall_priority": "high"
        }
      ]
      ```

      Severity: "high", "medium", "low"
      Priority: "high", "medium", "low"
    PROMPT
  end

  def parse_analysis_response(response, docs)
    begin
      # Handle JSON wrapped in markdown code blocks
      json_content = response
      if response.include?('```json')
        # Extract JSON from markdown code blocks
        match = response.match(/```json\s*(.*?)\s*```/m)
        json_content = match[1].strip if match
      elsif response.include?('```')
        # Extract from generic code blocks
        match = response.match(/```\s*(.*?)\s*```/m)
        json_content = match[1].strip if match
      end
      
      JSON.parse(json_content || response)
    rescue JSON::ParserError => e
      puts "⚠️  Error parsing analysis response: #{e.message}"
      []
    end
  end

  def post_analysis_results(results)
    return if results.empty?
    
    comment_body = build_comment_body(results)
    
    case @comment_mode
    when 'comment'
      post_pr_comment(comment_body)
    when 'review'
      post_pr_review(comment_body)
    else
      puts "⚠️  Unknown comment mode: #{@comment_mode}"
    end
  end

  def post_no_issues_comment
    comment_body = <<~COMMENT
      ## 📚 Documentation Drift Analysis

      ✅ **No documentation updates needed**

      I analyzed this pull request against the documentation knowledge base and found no documentation files that are likely to be affected by these changes.

      ---
      *This analysis was performed by the Documentation Drift Detective action using AI-powered classification.*
    COMMENT
    
    post_pr_comment(comment_body)
  end

  def build_comment_body(results)
    high_priority = results.select { |r| r['overall_priority'] == 'high' }
    medium_priority = results.select { |r| r['overall_priority'] == 'medium' }
    low_priority = results.select { |r| r['overall_priority'] == 'low' }
    
    total_issues = results.sum { |r| r['issues']&.length || 0 }
    
    comment = <<~COMMENT
      ## 📚 Documentation Drift Analysis
      
      🔍 **Analysis Summary:**
      - #{results.length} documentation files analyzed
      - #{total_issues} potential updates identified
      - #{high_priority.length} high-priority, #{medium_priority.length} medium-priority, #{low_priority.length} low-priority
    COMMENT
    
    if high_priority.any?
      comment << "\\n\\n### 🚨 High Priority Updates\\n\\n"
      comment << format_priority_section(high_priority)
    end
    
    if medium_priority.any?
      comment << "\\n\\n### ⚠️ Medium Priority Updates\\n\\n"
      comment << format_priority_section(medium_priority)
    end
    
    if low_priority.any?
      comment << "\\n\\n<details>\\n<summary>🔍 Low Priority Updates (#{low_priority.length} files)</summary>\\n\\n"
      comment << format_priority_section(low_priority)
      comment << "\\n</details>"
    end
    
    comment << <<~FOOTER
      
      ---
      *This analysis was performed by the Documentation Drift Detective action. Please review the suggestions and update documentation as needed.*
    FOOTER
    
    comment
  end

  def format_priority_section(priority_results)
    content = ""
    
    priority_results.each do |result|
      content << "#### 📄 `#{result['path']}`\\n\\n"
      
      if result['issues'] && result['issues'].any?
        result['issues'].each do |issue|
          severity_icon = case issue['severity']
          when 'high' then '🚨'
          when 'medium' then '⚠️'
          else '🔍'
          end
          
          content << "#{severity_icon} **#{issue['section']}**\\n"
          content << "- #{issue['issue']}\\n"
          content << "- *Suggestion: #{issue['suggestion']}*\\n\\n"
        end
      else
        content << "No specific issues identified, but this file may need review.\\n\\n"
      end
    end
    
    content
  end

  def post_pr_comment(body)
    github_api_request("POST", "/repos/#{@repository}/issues/#{@pr_number}/comments", {
      body: body
    })
    
    puts "✅ Posted analysis results as PR comment"
  end

  def post_pr_review(body)
    github_api_request("POST", "/repos/#{@repository}/pulls/#{@pr_number}/reviews", {
      body: body,
      event: "COMMENT"
    })
    
    puts "✅ Posted analysis results as PR review"
  end

  def output_summary(results)
    total_issues = results.sum { |r| r['issues']&.length || 0 }
    high_priority = results.count { |r| r['overall_priority'] == 'high' }
    
    puts "\\n📊 Analysis Summary:"
    puts "   Files analyzed: #{results.length}"
    puts "   Potential updates: #{total_issues}"
    puts "   High priority: #{high_priority}"
    
    # Set GitHub Actions outputs
    if ENV['GITHUB_OUTPUT']
      File.open(ENV['GITHUB_OUTPUT'], 'a') do |f|
        f.puts "docs-analyzed=#{results.length}"
        f.puts "potential-updates-found=#{total_issues}"
        f.puts "high-priority-updates=#{high_priority}"
      end
    else
      # Fallback for older versions or local testing
      puts "::set-output name=docs-analyzed::#{results.length}"
      puts "::set-output name=potential-updates-found::#{total_issues}"
      puts "::set-output name=high-priority-updates::#{high_priority}"
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
    else
      raise "Unsupported method: #{method}"
    end
    
    request['Authorization'] = "token #{@github_token}"
    request['Accept'] = 'application/vnd.github.v3+json'
    request['User-Agent'] = 'GitHub-Action-Docs-Drift-Detective'
    
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
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@copilot_token}"
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
      max_tokens: 3000,
      temperature: 0.1
    }.to_json
    
    response = http.request(request)
    
    if response.code.to_i >= 400
      puts "⚠️  Copilot API error: #{response.code} - #{response.body}"
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
    
    opts.on("--pr-number NUM", "Pull request number") do |num|
      options[:pr_number] = num.to_i
    end
    
    opts.on("--knowledge-base-path PATH", "Path to knowledge base file") do |path|
      options[:knowledge_base_path] = path
    end
    
    opts.on("--sensitivity-threshold LEVEL", "Minimum sensitivity level (0-3)") do |level|
      options[:sensitivity_threshold] = level.to_i
    end
    
    opts.on("--comment-mode MODE", "Comment mode (comment, review)") do |mode|
      options[:comment_mode] = mode
    end
    
    opts.on("--max-docs NUM", "Maximum docs to analyze") do |num|
      options[:max_docs] = num.to_i
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  begin
    detective = DocumentationDriftDetective.new(options)
    detective.analyze_documentation_drift
  rescue => e
    puts "❌ Error: #{e.message}"
    exit 1
  end
end
