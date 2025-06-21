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
    @analysis_scope = (options[:analysis_scope] || options[:net_width] || 'medium').to_s.downcase
    
    # Validate analysis_scope parameter
    unless ['narrow', 'medium', 'wide', 'aggressive'].include?(@analysis_scope)
      puts "⚠️  Invalid analysis-scope '#{@analysis_scope}', defaulting to 'medium'"
      @analysis_scope = 'medium'
    end
    
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
    puts "📏 Analysis scope: #{@analysis_scope} (#{get_analysis_scope_description(@analysis_scope)})"
    puts "📊 Total files in knowledge base: #{knowledge_base[:files].length}"
    
    # Get primary candidates that meet the sensitivity threshold
    primary_candidates = knowledge_base[:files].select do |doc|
      doc[:code_sensitivity_level] >= @sensitivity_threshold
    end
    
    # Get secondary candidates: lower sensitivity docs with potentially relevant technical patterns
    secondary_candidates = []
    if should_include_secondary_candidates? && @sensitivity_threshold > 0
      # Identify technical patterns from changed files
      changed_patterns = extract_technical_patterns_from_changes(pr_diff)
      
      if changed_patterns.any?
        secondary_candidates = knowledge_base[:files].select do |doc|
          doc[:code_sensitivity_level] < @sensitivity_threshold &&
          doc[:technical_patterns] &&
          (doc[:technical_patterns] & changed_patterns).any?
        end
      end
    end
    
    candidate_docs = primary_candidates + secondary_candidates
    
    # Add path-based candidates based on analysis scope
    path_candidates = []
    if should_include_path_candidates?
      changed_paths = pr_diff[:modified_paths]
      
      # Extract directory/module names from changed files
      changed_directories = changed_paths.map do |path|
        parts = path.split('/')
        # Get directory names and base filenames (without extensions)
        dir_parts = parts[0..-2] # All but the last part (filename)
        file_part = File.basename(parts.last, '.*') # Filename without extension
        [dir_parts, file_part].flatten.compact
      end.flatten.uniq
      
      # Find docs that mention changed paths/modules in their path or content patterns
      if changed_directories.any?
        path_candidates = knowledge_base[:files].select do |doc|
          !candidate_docs.include?(doc) &&
          changed_directories.any? do |changed_part|
            # Match if doc path contains the changed directory/file name
            doc[:path].downcase.include?(changed_part.downcase) ||
            # Or if key indicators mention the changed component
            (doc[:key_indicators] && doc[:key_indicators].any? { |indicator| 
              indicator.downcase.include?(changed_part.downcase) 
            })
          end
        end
        
        # Limit path candidates based on analysis scope
        max_path_candidates = get_max_path_candidates(@analysis_scope)
        path_candidates = path_candidates.first(max_path_candidates)
      end
    end
    
    candidate_docs += path_candidates
    
    puts "🎯 Primary candidates (sensitivity >= #{@sensitivity_threshold}): #{primary_candidates.length}"
    if primary_candidates.length > 0
      puts "📄 Primary candidate files:"
      primary_candidates.each do |doc|
        puts "   - #{doc[:path]} (sensitivity: #{doc[:code_sensitivity_level]}, staleness: #{doc[:staleness_risk_level]})"
      end
    end
    
    if secondary_candidates.length > 0
      puts "🔍 Secondary candidates (lower sensitivity, relevant patterns): #{secondary_candidates.length}"
      puts "📄 Secondary candidate files:"
      secondary_candidates.each do |doc|
        matching_patterns = doc[:technical_patterns] & extract_technical_patterns_from_changes(pr_diff)
        puts "   - #{doc[:path]} (sensitivity: #{doc[:code_sensitivity_level]}, patterns: #{matching_patterns.join(', ')})"
      end
    end
    
    if path_candidates.length > 0
      puts "🛤️  Path-based candidates (directory/module name matches): #{path_candidates.length}"
      puts "📄 Path-based candidate files:"
      path_candidates.each do |doc|
        puts "   - #{doc[:path]} (sensitivity: #{doc[:code_sensitivity_level]}, matched components)"
      end
    end
    
    # Add tertiary candidates for edge cases based on analysis scope
    tertiary_candidates = []
    
    if should_include_tertiary_candidates?
      # For small PRs, include high-staleness docs even with low sensitivity
      if should_include_small_pr_stale_docs? && pr_diff[:code_files].length <= get_small_pr_threshold(@analysis_scope)
        high_staleness_docs = knowledge_base[:files].select do |doc|
          !candidate_docs.include?(doc) &&
          doc[:staleness_risk_level] && doc[:staleness_risk_level] >= get_staleness_threshold(@analysis_scope)
        end
        
        if high_staleness_docs.any?
          max_stale_candidates = get_max_stale_candidates(@analysis_scope)
          stale_candidates = high_staleness_docs.first(max_stale_candidates)
          tertiary_candidates += stale_candidates
          puts "🕰️  Small PR detected: including #{stale_candidates.length} high-staleness docs as tertiary candidates"
        end
      end
      
      # Include docs with very high staleness regardless of sensitivity, but limit count
      max_very_stale = get_max_very_stale_candidates(@analysis_scope)
      if tertiary_candidates.length < max_very_stale
        very_stale_docs = knowledge_base[:files].select do |doc|
          !candidate_docs.include?(doc) &&
          !tertiary_candidates.include?(doc) &&
          doc[:staleness_risk_level] == 3
        end
        
        additional_stale = very_stale_docs.first(max_very_stale - tertiary_candidates.length)
        if additional_stale.any?
          tertiary_candidates += additional_stale
          puts "⚠️  Including #{additional_stale.length} very stale docs as tertiary candidates"
        end
      end
      
      # Include high-confidence API documentation for any API-related changes
      if should_include_api_docs? && extract_technical_patterns_from_changes(pr_diff).any? { |p| p.include?('API') }
        min_api_confidence = get_min_api_confidence(@analysis_scope)
        api_docs = knowledge_base[:files].select do |doc|
          !candidate_docs.include?(doc) &&
          !tertiary_candidates.include?(doc) &&
          doc[:doc_category] && doc[:doc_category].include?('API') &&
          doc[:confidence_score] && doc[:confidence_score] >= min_api_confidence
        end
        
        if api_docs.length > 0
          max_api_candidates = get_max_api_candidates(@analysis_scope)
          additional_api = api_docs.first(max_api_candidates)
          tertiary_candidates += additional_api
          puts "🔌 API changes detected: including #{additional_api.length} high-confidence API docs as tertiary candidates"
        end
      end
      
      # Include setup/installation guides for config or dependency changes
      if should_include_setup_docs?
        config_patterns = extract_technical_patterns_from_changes(pr_diff)
        if config_patterns.any? { |p| p.include?('Configuration') || p.include?('Dependencies') }
          setup_docs = knowledge_base[:files].select do |doc|
            !candidate_docs.include?(doc) &&
            !tertiary_candidates.include?(doc) &&
            doc[:doc_category] && (doc[:doc_category].include?('Setup') || doc[:doc_category].include?('Installation'))
          end
          
          if setup_docs.length > 0
            max_setup_candidates = get_max_setup_candidates(@analysis_scope)
            additional_setup = setup_docs.first(max_setup_candidates)
            tertiary_candidates += additional_setup
            puts "⚙️  Configuration changes detected: including #{additional_setup.length} setup/installation docs as tertiary candidates"
          end
        end
      end
    end
    
    candidate_docs += tertiary_candidates
    
    if tertiary_candidates.length > 0
      puts "🎯 Tertiary candidates (edge cases): #{tertiary_candidates.length}"
      puts "📄 Tertiary candidate files:"
      tertiary_candidates.each do |doc|
        reason = []
        reason << "very stale" if doc[:staleness_risk_level] == 3
        reason << "small PR + stale" if pr_diff[:code_files].length <= 3 && doc[:staleness_risk_level] >= 2
        reason << "API doc" if doc[:doc_category] && doc[:doc_category].include?('API')
        reason << "setup/config doc" if doc[:doc_category] && (doc[:doc_category].include?('Setup') || doc[:doc_category].include?('Installation'))
        
        puts "   - #{doc[:path]} (sensitivity: #{doc[:code_sensitivity_level]}, staleness: #{doc[:staleness_risk_level]}, reason: #{reason.join(', ')})"
      end
    end
    
    # If no candidates at all, return early
    if candidate_docs.empty?
      puts "ℹ️  No documentation files meet the criteria"
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
      You are a documentation drift detection expert. Determine which documentation files might contain OUTDATED content due to the specific code changes in this PR.

      ## Pull Request Changes
      **Files modified:** #{changed_files.length} files
      **Key changed files:**
      #{changed_files.map { |f| "- #{f}" }.join("\\n")}
      
      **Change summary:**
      - #{pr_diff[:total_additions]} lines added
      - #{pr_diff[:total_deletions]} lines deleted

      ## Documentation Files to Evaluate
      #{JSON.pretty_generate(docs_summary)}

      ## FOCUS ON DRIFT DETECTION
      
      Only flag documentation that is likely to contain FACTUALLY INCORRECT information due to these specific changes. The key test is: **Would a user following this documentation encounter broken code, wrong behavior, or incorrect information?**
      
      Ask yourself these specific questions:
      
      1. **Does this doc contain exact references to changed files/functions/classes?**
      2. **Are there code examples that would now fail or behave differently?**
      3. **Does it describe APIs/endpoints/methods that were modified or removed?**
      4. **Are there step-by-step instructions that would no longer work?**
      5. **Does it reference specific configuration values, paths, or parameters that changed?**
      
      **CRITICAL: Being "related" is NOT enough - content must be factually wrong**
      
      **DO NOT flag docs just because:**
      - They're about the same general topic/area as the changes
      - They could benefit from general improvements or additions
      - They're missing new information (unless old info was specifically removed)
      - They could have more examples added
      - They mention the same files/components but describe different aspects that remain valid
      - They're high-level guides that remain accurate despite implementation changes

      **Analysis strategy**: #{get_ai_analysis_strategy(@analysis_scope)}

      Respond with a JSON array of documentation that likely contains OUTDATED content:
      ```json
      [
        {
          "path": "docs/api.md",
          "likelihood": "high",
          "reasoning": "Contains specific code examples calling AuthController.authenticate() which was renamed to verify() in this PR - users would get method not found errors",
          "priority": 3
        }
      ]
      ```

      Likelihood: "high" (likely contains outdated code/references), "medium" (might contain outdated info), "low" (small chance of outdated content)
      Priority: 1-3 (3 = most important to check for outdated content)
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
          # Include low-likelihood docs but mark them as such
          skipped_docs << {
            path: result['path'],
            likelihood: result['likelihood'],
            reasoning: result['reasoning']
          }
          
          # Still add to affected docs but with lower confidence flag
          affected_docs << doc.merge(
            analysis_likelihood: result['likelihood'],
            analysis_reasoning: result['reasoning'],
            analysis_priority: result['priority'] || 1,
            low_confidence: true
          )
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
    
    analysis_results = parse_analysis_response(response, docs_with_content)
    
    # Preserve low_confidence metadata from AI identification
    analysis_results.map do |result|
      original_doc = docs.find { |d| d[:path] == result['path'] }
      if original_doc && original_doc[:low_confidence]
        result['analysis_metadata'] = { 'low_confidence' => true }
      end
      result
    end
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
      You are a documentation drift detection expert. Your job is to identify content that has become OUTDATED due to the specific code changes in this PR. 

      ## Code Changes in This PR
      **Modified files:**
      #{changed_files.map { |f| "- #{f}" }.join("\\n")}
      
      ## Documentation Files to Analyze
      #{JSON.pretty_generate(docs_for_analysis)}

      ## CRITICAL INSTRUCTIONS
      
      **Your ONLY job is to identify content that has become FACTUALLY INCORRECT due to these specific code changes.**
      
      **The key test: Would a user following this documentation encounter broken functionality, wrong behavior, or get incorrect results?**
      
      **ONLY flag content that:**
      1. **Contains exact code examples that now fail or behave differently** - Look for specific function calls, imports, syntax
      2. **Describes specific processes/workflows that these changes broke** - Not general processes, but exact steps that no longer work
      3. **References specific files, classes, methods, or endpoints that were renamed/removed/changed** - Must be exact matches, not just similar
      4. **Has configuration examples with values/paths/settings that these changes invalidated** - Specific config that would now cause errors
      5. **Contains URLs, endpoints, or API calls that these changes modified** - Must be specific technical references
      
      **DO NOT flag content that:**
      - Is about the same general topic but describes different aspects that remain valid
      - Mentions the same components but in ways that are still accurate
      - Could be enhanced with new information (unless old information is now wrong)
      - Is missing coverage of new features (unless it explicitly describes old behavior)
      - Is a high-level guide that remains conceptually correct despite implementation changes
      - Uses general terminology that might overlap with changed code but describes valid concepts
      
      **Example of what TO flag:** "Call AuthController.authenticate(token)" when that method was renamed to verify()
      **Example of what NOT to flag:** "This app uses authentication" when AuthController methods changed but authentication still exists

      ## RESPONSE FORMAT REQUIREMENTS
      
      For each issue you identify:
      - `section_name`: Keep it simple - just the section name, NO line numbers
      - `line_reference`: Leave empty "" (do not make up line numbers)
      - `outdated_content`: ONE clear sentence describing what is now FACTUALLY WRONG or BROKEN
      - `suggested_change`: ONE clear sentence describing how to fix the broken/incorrect content
      - Keep both sentences concise and actionable
      - Focus on what would fail or mislead users, not what could be improved

      **If the documentation doesn't contain anything that's specifically broken or factually incorrect due to these changes, return an empty issues array.**

      Respond with JSON using this EXACT schema:
      ```json
      [
        {
          "path": "docs/api.md",
          "issues": [
            {
              "section_name": "Authentication section",
              "line_reference": "",
              "outdated_content": "Shows code example `AuthController.authenticate(token)` but this method was renamed to `verify()` and would now throw a NoMethodError",
              "suggested_change": "Update the code example to use `AuthController.verify(token)` instead of the removed authenticate method",
              "severity": "high"
            }
          ],
          "overall_priority": "high"
        }
      ]
      ```

      **Required fields:**
      - `section_name`: Name of the section (NO line numbers unless you can see them in the content)
      - `line_reference`: Leave empty "" unless you can identify specific lines from the provided content
      - `outdated_content`: ONE sentence describing what is outdated
      - `suggested_change`: ONE sentence describing the fix
      - `severity`: "high" (broken examples/links), "medium" (misleading info), "low" (minor inaccuracies)

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
      
      parsed_response = JSON.parse(json_content || response)
      
      # Validate and normalize the schema
      normalized_response = parsed_response.map do |result|
        # Ensure required fields exist
        result['path'] = result['path'] || 'unknown'
        result['overall_priority'] = result['overall_priority'] || 'medium'
        
        # Normalize issues array
        if result['issues']
          result['issues'] = result['issues'].map do |issue|
            normalized_issue = {
              'section_name' => issue['section_name'] || issue['section'] || 'Unknown section',
              'line_reference' => issue['line_reference'] || '',
              'outdated_content' => issue['outdated_content'] || issue['issue'] || 'Content may be outdated',
              'suggested_change' => issue['suggested_change'] || issue['suggestion'] || 'Review and update as needed',
              'severity' => issue['severity'] || 'medium'
            }
            
            # Validate sentence length (should be reasonable)
            if normalized_issue['outdated_content'].length > 200
              puts "⚠️  Long outdated_content field detected - consider shortening"
            end
            if normalized_issue['suggested_change'].length > 200
              puts "⚠️  Long suggested_change field detected - consider shortening"
            end
            
            normalized_issue
          end
        else
          result['issues'] = []
        end
        
        result
      end
      
      puts "✅ Successfully parsed and normalized analysis response with #{normalized_response.length} files"
      puts "📊 Total issues found: #{normalized_response.sum { |r| r['issues'].length }}"
      normalized_response
    rescue JSON::ParserError => e
      puts "⚠️  Error parsing analysis response: #{e.message}"
      puts "📋 Raw response preview: #{response[0..200]}#{response.length > 200 ? '...' : ''}"
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
    total_issues = results.sum { |r| r['issues']&.length || 0 }
    
    comment = <<~COMMENT
      ## 📚 Documentation Drift Analysis
      
      **Analysis Summary:** #{results.length} files analyzed, #{total_issues} potential updates identified
      
    COMMENT
    
    if total_issues > 0
      comment << format_all_recommendations(results)
    else
      comment << "No documentation updates needed.\n\n"
    end
    
    comment << <<~FOOTER
      ---
      *This analysis was performed by the Documentation Drift Detective action. Please review the suggestions and update documentation as needed.*
    FOOTER
    
    comment
  end

  def format_all_recommendations(results)
    content = ""
    
    # Separate issues by both AI confidence and issue severity
    high_medium_issues = []
    low_severity_issues = []
    low_confidence_issues = []
    
    results.each do |result|
      file_path = result['path']
      is_low_confidence = result.dig('analysis_metadata', 'low_confidence') || false
      
      if result['issues'] && result['issues'].any?
        result['issues'].each do |issue|
          item = {
            file_path: file_path,
            issue: issue,
            low_confidence: is_low_confidence
          }
          
          if is_low_confidence
            low_confidence_issues << item
          elsif issue['severity'] == 'low'
            low_severity_issues << item
          else
            high_medium_issues << item
          end
        end
      end
    end
    
    # Group high/medium confidence and severity issues by file
    if high_medium_issues.any?
      content << format_issues_by_file(high_medium_issues)
    end
    
    # Combine low severity and low confidence for suppressed section
    suppressed_issues = low_severity_issues + low_confidence_issues
    
    if suppressed_issues.any?
      low_conf_count = low_confidence_issues.length
      low_sev_count = low_severity_issues.length
      
      summary_text = if low_conf_count > 0 && low_sev_count > 0
                       "low confidence (#{low_conf_count}) and low priority (#{low_sev_count})"
                     elsif low_conf_count > 0
                       "low confidence (#{low_conf_count})"
                     else
                       "low priority (#{low_sev_count})"
                     end
      
      content << "\n<details>\n"
      content << "<summary>Suggestions suppressed due to #{summary_text}</summary>\n\n"
      content << format_issues_by_file(suppressed_issues)
      content << "</details>\n"
    end
    
    content + "\n"
  end

  def format_issues_by_file(issues)
    content = ""
    
    # Group by file
    issues_by_file = issues.group_by { |item| item[:file_path] }
    
    issues_by_file.each do |file_path, file_issues|
      content << "**#{file_path}**\n"
      
      file_issues.each do |item|
        issue = item[:issue]
        
        # Parse section information to build a specific link
        section_name = issue['section_name'] || issue['section'] || 'Unknown section'
        line_reference = issue['line_reference'] || ''
        
        # Build the file link
        if line_reference && !line_reference.empty?
          # Try to extract line numbers from line_reference
          if line_reference.match?(/\d+/)
            issue_link = build_file_link(file_path, section_name, line_reference)
          else
            issue_link = build_file_link(file_path, section_name, nil)
          end
        else
          issue_link = build_file_link(file_path, section_name, nil)
        end
        
        # Format using the new structured fields
        outdated_content = issue['outdated_content'] || issue['issue'] || 'Content may be outdated'
        suggested_change = issue['suggested_change'] || issue['suggestion'] || 'Review and update as needed'
        
        content << "* #{issue_link}: #{outdated_content} #{suggested_change}\n"
      end
      
      content << "\n"
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

  def get_pr_info
    # Get PR details to get the head branch
    pr_info = github_api_request("GET", "/repos/#{@repository}/pulls/#{@pr_number}")
    return nil unless pr_info
    
    {
      head_branch: pr_info['head']['ref'],
      head_sha: pr_info['head']['sha'],
      base_branch: pr_info['base']['ref']
    }
  end

  def build_file_link(file_path, section_name = nil, line_reference = nil)
    # Get PR info for the head branch
    pr_info = @pr_info ||= get_pr_info
    return file_path unless pr_info
    
    branch = pr_info[:head_branch]
    base_url = "https://github.com/#{@repository}/blob/#{branch}/#{file_path}"
    
    # Handle line references more simply
    url = if line_reference && line_reference.match?(/\d+/)
            # Extract just the numbers and create line anchor
            lines = line_reference.scan(/\d+/)
            if lines.length == 2
              "#{base_url}#L#{lines[0]}-L#{lines[1]}"
            elsif lines.length == 1
              "#{base_url}#L#{lines[0]}"
            else
              base_url
            end
          else
            base_url
          end
    
    # Create cleaner display text
    display_text = if section_name && !section_name.empty?
                     "#{File.basename(file_path)} (#{section_name})"
                   else
                     File.basename(file_path)
                   end
    
    "[#{display_text}](#{url})"
  end

  def extract_technical_patterns_from_changes(pr_diff)
    patterns = []
    
    pr_diff[:code_files].each do |file|
      filename = file['filename']
      
      # Extract directory-based patterns (casting wider net)
      path_parts = filename.split('/')
      path_parts.each do |part|
        case part.downcase
        when /app/, /application/
          patterns += ['Application/Core', 'Business Logic']
        when /controller/
          patterns += ['API/Routing', 'MVC/Controllers', 'HTTP/REST', 'Request/Response']
        when /model/
          patterns += ['Database/Models', 'Data/Validation', 'ORM/ActiveRecord', 'Business Logic']
        when /view/, /template/
          patterns += ['UI/Views', 'Templates/Rendering', 'Frontend/Forms', 'User Interface']
        when /migration/
          patterns += ['Database/Schema', 'Database/Migrations', 'Data Structure']
        when /route/
          patterns += ['API/Routing', 'URL/Routing', 'Navigation']
        when /config/
          patterns += ['Configuration', 'Environment/Setup', 'Application/Settings']
        when /test/, /spec/
          patterns += ['Testing/Unit', 'Testing/Integration', 'Quality Assurance']
        when /api/
          patterns += ['API/Endpoints', 'API/Documentation', 'External/Integration']
        when /auth/
          patterns += ['Authentication/Authorization', 'Security/Access', 'User/Management']
        when /job/, /worker/
          patterns += ['Background/Jobs', 'Processing/Queue', 'Async/Operations']
        when /mailer/
          patterns += ['Email/Notifications', 'Communication/Messages']
        when /helper/
          patterns += ['Utility/Helpers', 'Code/Organization', 'DRY/Principles']
        when /service/
          patterns += ['Service/Layer', 'Business/Logic', 'Architecture/Patterns']
        when /lib/, /library/
          patterns += ['Library/Code', 'Shared/Utilities', 'Core/Logic']
        when /db/, /database/
          patterns += ['Database/Schema', 'Data/Persistence', 'Storage/Management']
        when /public/, /assets/
          patterns += ['Static/Assets', 'Public/Resources', 'Frontend/Assets']
        end
      end
      
      # Map file extensions and names to technical patterns (expanded coverage)
      case filename
      when /controller/i
        patterns += ['API/Routing', 'MVC/Controllers', 'HTTP/REST', 'Request/Response']
      when /model/i
        patterns += ['Database/Models', 'Data/Validation', 'ORM/ActiveRecord', 'Business Logic']
      when /view|erb|html/i
        patterns += ['UI/Views', 'Templates/Rendering', 'Frontend/Forms', 'User Interface']
      when /migration/i
        patterns += ['Database/Schema', 'Database/Migrations', 'Data Structure']
      when /route/i
        patterns += ['API/Routing', 'URL/Routing', 'Navigation']
      when /config/i
        patterns += ['Configuration', 'Environment/Setup', 'Application/Settings']
      when /test|spec/i
        patterns += ['Testing/Unit', 'Testing/Integration', 'Quality Assurance']
      when /api/i
        patterns += ['API/Endpoints', 'API/Documentation', 'External/Integration']
      when /auth/i
        patterns += ['Authentication/Authorization', 'Security/Access', 'User/Management']
      when /css|scss|style/i
        patterns += ['UI/Styling', 'Frontend/CSS', 'Visual/Design']
      when /js|javascript|ts|typescript/i
        patterns += ['Frontend/JavaScript', 'UI/Interaction', 'Client/Side']
      when /helper/i
        patterns += ['Utility/Helpers', 'Code/Organization', 'DRY/Principles']
      when /seed/i
        patterns += ['Database/Seeds', 'Sample/Data', 'Initial/Setup']
      when /lib/i
        patterns += ['Library/Code', 'Shared/Utilities', 'Core/Logic']
      when /service/i
        patterns += ['Service/Layer', 'Business/Logic', 'Architecture/Patterns']
      when /job|worker/i
        patterns += ['Background/Jobs', 'Processing/Queue', 'Async/Operations']
      when /mailer/i
        patterns += ['Email/Notifications', 'Communication/Messages']
      when /gemfile|package\.json/i
        patterns += ['Dependencies/Management', 'Package/Configuration']
      when /dockerfile|docker/i
        patterns += ['Infrastructure/DevOps', 'Deployment/Containers']
      when /yml|yaml/i
        patterns += ['Configuration', 'Infrastructure/DevOps', 'CI/CD']
      end
      
      # Also check for specific patterns in the diff content if available
      if file['patch']
        patch_content = file['patch'].downcase
        
        # Database related
        patterns += ['Database/Schema', 'Data Structure'] if patch_content.match?(/schema|table|column|index|constraint/)
        patterns += ['Database/Migrations'] if patch_content.match?(/migrate|migration|add_column|create_table/)
        patterns += ['Data/Validation'] if patch_content.match?(/valid|validate|presence|format|length/)
        
        # API and routing
        patterns += ['API/Routing', 'URL/Routing'] if patch_content.match?(/route|endpoint|path|url/)
        patterns += ['API/Endpoints'] if patch_content.match?(/get|post|put|delete|patch|api/)
        
        # Authentication and security
        patterns += ['Authentication/Authorization'] if patch_content.match?(/auth|login|password|token|session/)
        patterns += ['Security/Access'] if patch_content.match?(/permit|allow|secure|protect/)
        
        # UI and forms
        patterns += ['UI/Forms', 'Frontend/Forms'] if patch_content.match?(/form|input|submit|field/)
        patterns += ['User Interface', 'UI/Views'] if patch_content.match?(/render|display|show|view/)
        
        # Configuration and setup
        patterns += ['Configuration', 'Environment/Setup'] if patch_content.match?(/config|setting|environment|setup/)
        
        # Testing
        patterns += ['Testing/Unit', 'Testing/Integration'] if patch_content.match?(/test|spec|expect|assert/)
        
        # Background jobs and async
        patterns += ['Background/Jobs', 'Processing/Queue'] if patch_content.match?(/job|worker|queue|async|background/)
        
        # Email and notifications
        patterns += ['Email/Notifications'] if patch_content.match?(/mail|email|notify|message/)
        
        # Performance and caching
        patterns += ['Performance/Optimization'] if patch_content.match?(/cache|optimize|performance|memory/)
        
        # External integrations
        patterns += ['Integration/External'] if patch_content.match?(/webhook|external|third.party|integration/)
        
        # Business logic
        patterns += ['Business Logic', 'Core/Logic'] if patch_content.match?(/process|calculate|logic|rule/)
      end
    end
    
    patterns.uniq
  end

  # Analysis scope configuration methods
  def get_analysis_scope_description(analysis_scope)
    case analysis_scope
    when 'narrow'
      'conservative analysis, fewer candidates'
    when 'medium'
      'balanced analysis, moderate candidates'
    when 'wide'
      'comprehensive analysis, many candidates'
    when 'aggressive'
      'exhaustive analysis, maximum candidates'
    else
      'unknown'
    end
  end

  def should_include_secondary_candidates?
    %w[medium wide aggressive].include?(@analysis_scope)
  end

  def should_include_path_candidates?
    %w[wide aggressive].include?(@analysis_scope)
  end

  def should_include_tertiary_candidates?
    %w[medium wide aggressive].include?(@analysis_scope)
  end

  def should_include_small_pr_stale_docs?
    %w[wide aggressive].include?(@analysis_scope)
  end

  def should_include_api_docs?
    %w[medium wide aggressive].include?(@analysis_scope)
  end

  def should_include_setup_docs?
    %w[wide aggressive].include?(@analysis_scope)
  end

  def get_max_path_candidates(analysis_scope)
    case analysis_scope
    when 'wide'
      5
    when 'aggressive'
      10
    else
      3
    end
  end

  def get_small_pr_threshold(analysis_scope)
    case analysis_scope
    when 'aggressive'
      5  # Consider larger PRs as "small"
    else
      3  # Default threshold
    end
  end

  def get_staleness_threshold(analysis_scope)
    case analysis_scope
    when 'aggressive'
      1  # Include any stale docs
    else
      2  # Default staleness threshold
    end
  end

  def get_max_stale_candidates(analysis_scope)
    case analysis_scope
    when 'wide'
      4
    when 'aggressive'
      6
    else
      3
    end
  end

  def get_max_very_stale_candidates(analysis_scope)
    case analysis_scope
    when 'narrow'
      1
    when 'medium'
      2
    when 'wide'
      3
    when 'aggressive'
      5
    else
      2
    end
  end

  def get_min_api_confidence(analysis_scope)
    case analysis_scope
    when 'medium'
      0.8  # High confidence only
    when 'wide'
      0.6  # Medium to high confidence
    when 'aggressive'
      0.4  # Include lower confidence
    else
      0.8
    end
  end

  def get_max_api_candidates(analysis_scope)
    case analysis_scope
    when 'medium'
      2
    when 'wide'
      3
    when 'aggressive'
      5
    else
      2
    end
  end

  def get_max_setup_candidates(analysis_scope)
    case analysis_scope
    when 'wide'
      3
    when 'aggressive'
      4
    else
      2
    end
  end

  def get_ai_analysis_strategy(analysis_scope)
    case analysis_scope
    when 'narrow'
      'Be very conservative - only flag documentation with explicit, exact references to the changed code that would now be factually wrong or cause failures. Require clear evidence of broken functionality.'
    when 'medium'
      'Be selective - flag documentation that contains specific references to the changed code that would mislead users or cause errors. Focus on concrete drift, not general relatedness.'
    when 'wide'
      'Be thorough - include documentation that contains direct references to changed components where the information would now be incorrect. Still require factual incorrectness, not just topical overlap.'
    when 'aggressive'
      'Be comprehensive - include any documentation that contains specific technical details that these changes made factually incorrect. Focus on what would mislead or break for users, not general improvements.'
    else
      'Focus on detecting factually incorrect content rather than related content. Only flag what would now cause user confusion or failures due to being wrong.'
    end
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
    
    opts.on("--analysis-scope LEVEL", "Analysis scope (narrow, medium, wide, aggressive)") do |level|
      options[:analysis_scope] = level
    end
    
    # Keep backwards compatibility with the old parameter name
    opts.on("--net-width LEVEL", "Analysis scope (narrow, medium, wide, aggressive) [deprecated: use --analysis-scope]") do |level|
      options[:net_width] = level
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
