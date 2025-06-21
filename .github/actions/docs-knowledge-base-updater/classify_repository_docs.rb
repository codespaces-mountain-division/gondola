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

class RepositoryDocumentationClassifier
  def initialize(options = {})
    @github_token = ENV['GITHUB_TOKEN'] || options[:github_token]
    @copilot_token = ENV['COPILOT_TOKEN'] || options[:copilot_token] || @github_token
    @repository = options[:repository]
    @output_path = options[:output_path] || '.github/docs-knowledge-base.json'
    @docs_patterns = parse_patterns(options[:docs_patterns] || "**/*.md\n**/*.markdown")
    @exclude_patterns = parse_patterns(options[:exclude_patterns] || "node_modules/**\n.git/**")
    
    validate_inputs!
  end

  def classify_repository
    puts "🔍 Discovering documentation files in #{@repository}..."
    
    files = discover_documentation_files
    puts "📄 Found #{files.length} documentation files"
    
    if files.empty?
      puts "ℹ️  No documentation files found"
      return create_empty_knowledge_base
    end

    puts "🤖 Classifying files using AI..."
    classified_files = classify_files(files)
    
    puts "💾 Generating knowledge base..."
    knowledge_base = generate_knowledge_base(classified_files)
    
    save_knowledge_base(knowledge_base)
    output_summary(knowledge_base)
    
    knowledge_base
  end

  private

  def validate_inputs!
    raise "GitHub token is required" unless @github_token
    raise "Repository is required" unless @repository
    raise "Copilot token is required" unless @copilot_token
  end

  def parse_patterns(patterns_string)
    return [] unless patterns_string
    patterns_string.split("\n").map(&:strip).reject(&:empty?)
  end

  def discover_documentation_files
    files = []
    
    # Debug: Show current working directory
    puts "🔍 Working directory: #{Dir.pwd}"
    
    # Scan local filesystem instead of GitHub API since we're in a checkout
    @docs_patterns.each do |pattern|
      pattern_matches = Dir.glob(pattern, File::FNM_DOTMATCH)
      puts "🔍 Pattern '#{pattern}' found #{pattern_matches.length} matches"
      
      pattern_matches.each do |file_path|
        # Skip if file doesn't exist or is a directory
        next unless File.exist?(file_path) && File.file?(file_path)
        
        # Check if file matches any exclude pattern
        excluded = @exclude_patterns.any? { |exclude_pattern| 
          File.fnmatch(exclude_pattern, file_path, File::FNM_PATHNAME) 
        }
        
        if excluded
          puts "🚫 Excluding #{file_path} (matched exclude pattern)"
        else
          puts "✅ Including #{file_path}"
        end
        
        next if excluded
        
        # Get file stats
        stat = File.stat(file_path)
        
        files << {
          path: file_path,
          sha: Digest::SHA1.hexdigest(File.read(file_path)), # Generate SHA for consistency
          size: stat.size
        }
      end
    end
    
    files.uniq { |f| f[:path] } # Remove duplicates based on path
  end

  def classify_files(files)
    classified_files = []
    
    # Process files in batches to avoid API limits
    files.each_slice(10) do |batch|
      batch_content = fetch_batch_content(batch)
      
      # Filter out files that couldn't be fetched or are too large
      valid_files = batch_content.select { |f| f[:content] && f[:content].length < 50000 }
      
      if valid_files.any?
        classifications = classify_batch(valid_files)
        classified_files.concat(classifications)
      end
      
      # Be respectful of API limits
      sleep(0.5)
    end
    
    classified_files
  end

  def fetch_batch_content(files)
    files.map do |file|
      content = fetch_file_content(file[:path])
      
      {
        path: file[:path],
        sha: file[:sha],
        size: file[:size],
        content: content
      }
    end
  end

  def fetch_file_content(file_path)
    return nil unless File.exist?(file_path) && File.readable?(file_path)
    
    # Read file content
    content = File.read(file_path)
    
    # Handle encoding issues
    content = content.force_encoding('UTF-8')
    unless content.valid_encoding?
      content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    content
  rescue => e
    puts "⚠️  Error reading #{file_path}: #{e.message}"
    nil
  end

  def classify_batch(files)
    # Prepare the batch for classification
    files_for_classification = files.map do |file|
      {
        file_path: file[:path],
        file_name: File.basename(file[:path]),
        file_size: file[:content].length,
        content_preview: file[:content][0, 3000] # First 3000 chars for classification
      }
    end
    
    # Use our existing classification prompt and schema
    prompt = build_classification_prompt(files_for_classification)
    
    response = copilot_api_request(prompt)
    return [] unless response
    
    parse_classification_response(response, files)
  end

  def build_classification_prompt(files)
    files_json = files.map.with_index do |file, index|
      {
        document_number: index + 1,
        file_path: file[:file_path],
        file_name: file[:file_name],
        file_size: file[:file_size],
        content_preview: file[:content_preview]
      }
    end

    <<~PROMPT
      You are a documentation classification expert. Analyze the following #{files.length} documentation files and classify each one across four key dimensions for code change impact assessment.

      For each document, provide:

      1. **Code Sensitivity Level** (0-3): How sensitive is this documentation to code changes?
         - 0: Not sensitive (general docs, external content, non-technical)
         - 1: Low sensitivity (broad concepts, no specific implementation details)
         - 2: Medium sensitivity (references specific components, modules, patterns)
         - 3: High sensitivity (mentions function names, signatures, specific code structure)

      2. **Staleness Risk** (1-3): How likely is this documentation to become outdated?
         - 1: Low risk - Stable concepts that rarely change
         - 2: Medium risk - May become outdated as features evolve
         - 3: High risk - Likely to become outdated quickly due to frequent changes

      3. **Technical Patterns** (array): Which technical areas does this document cover?
         - API/Routing, Database/Schema, Background/Jobs, Authentication/Authorization
         - Frontend/UI, Infrastructure/DevOps, Testing/QA, Configuration/Environment
         - Data/Analytics, Integration/External, Performance/Optimization
         - Security/Compliance, Documentation/Process

      4. **Document Type**: High-specificity classification
         - API Reference (Beginner), API Reference (Advanced), Setup Guide (Quick Start)
         - Setup Guide (Comprehensive), Tutorial (Step-by-Step), Tutorial (Interactive)
         - Architecture Overview, Architecture Deep-Dive, Process Documentation
         - Troubleshooting Guide, Contributing Guidelines, Reference Documentation
         - Policy/Compliance, Release Notes, FAQ/Help, Personal Notes, External Links

      Files to classify:
      #{JSON.pretty_generate(files_json)}

      Respond with a JSON array containing one object per document with this exact schema:
      {
        "document_number": 1,
        "code_sensitivity_level": 2,
        "staleness_risk": 3,
        "technical_patterns": ["API/Routing", "Authentication/Authorization"],
        "doc_category": "API Reference (Advanced)",
        "confidence_score": 0.85,
        "key_indicators": ["function signatures", "endpoint documentation", "authentication flow"]
      }
    PROMPT
  end

  def parse_classification_response(response, files)
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
      
      classifications = JSON.parse(json_content || response)
      
      classified_files = []
      classifications.each do |classification|
        doc_num = classification['document_number'] - 1
        next if doc_num < 0 || doc_num >= files.length
        
        file = files[doc_num]
        
        classified_files << {
          path: file[:path],
          sha: file[:sha],
          size: file[:size],
          code_sensitivity_level: classification['code_sensitivity_level'],
          staleness_risk: classification['staleness_risk'],
          technical_patterns: classification['technical_patterns'] || [],
          doc_category: classification['doc_category'],
          confidence_score: classification['confidence_score'],
          key_indicators: classification['key_indicators'] || [],
          classified_at: Time.now.iso8601
        }
      end
      
      classified_files
    rescue JSON::ParserError => e
      puts "⚠️  Error parsing classification response: #{e.message}"
      []
    end
  end

  def generate_knowledge_base(classified_files)
    # Calculate repository-level statistics
    total_files = classified_files.length
    return create_empty_knowledge_base if total_files == 0
    
    # Sensitivity distribution
    sensitivity_counts = classified_files.group_by { |f| f[:code_sensitivity_level] }.transform_values(&:length)
    staleness_counts = classified_files.group_by { |f| f[:staleness_risk] }.transform_values(&:length)
    
    # Technical patterns
    all_patterns = classified_files.flat_map { |f| f[:technical_patterns] }.compact
    pattern_counts = all_patterns.group_by(&:itself).transform_values(&:length)
    
    # Document categories
    category_counts = classified_files.group_by { |f| f[:doc_category] }.transform_values(&:length)
    
    # High-risk files (high sensitivity + high staleness)
    high_risk_files = classified_files.select { |f| f[:code_sensitivity_level] >= 2 && f[:staleness_risk] >= 2 }
    
    {
      repository: @repository,
      generated_at: Time.now.iso8601,
      total_files: total_files,
      
      # Summary statistics
      avg_code_sensitivity: (classified_files.sum { |f| f[:code_sensitivity_level] }.to_f / total_files).round(2),
      avg_staleness_risk: (classified_files.sum { |f| f[:staleness_risk] }.to_f / total_files).round(2),
      avg_confidence: (classified_files.sum { |f| f[:confidence_score] }.to_f / total_files).round(2),
      
      # Risk indicators
      high_sensitivity_files: sensitivity_counts[3] || 0,
      high_staleness_files: staleness_counts[3] || 0,
      high_risk_files: high_risk_files.length,
      
      # Distribution data
      sensitivity_distribution: sensitivity_counts,
      staleness_distribution: staleness_counts,
      top_patterns: pattern_counts.sort_by { |_, count| -count }.first(10).to_h,
      top_categories: category_counts.sort_by { |_, count| -count }.first(10).to_h,
      
      # File-level data for drift detection
      files: classified_files.map do |file|
        {
          path: file[:path],
          sha: file[:sha],
          code_sensitivity_level: file[:code_sensitivity_level],
          staleness_risk: file[:staleness_risk],
          technical_patterns: file[:technical_patterns],
          doc_category: file[:doc_category],
          confidence_score: file[:confidence_score],
          key_indicators: file[:key_indicators],
          classified_at: file[:classified_at]
        }
      end
    }
  end

  def create_empty_knowledge_base
    {
      repository: @repository,
      generated_at: Time.now.iso8601,
      total_files: 0,
      avg_code_sensitivity: 0,
      avg_staleness_risk: 0,
      avg_confidence: 0,
      high_sensitivity_files: 0,
      high_staleness_files: 0,
      high_risk_files: 0,
      sensitivity_distribution: {},
      staleness_distribution: {},
      top_patterns: {},
      top_categories: {},
      files: []
    }
  end

  def save_knowledge_base(knowledge_base)
    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(@output_path))
    
    # Write the knowledge base
    File.write(@output_path, JSON.pretty_generate(knowledge_base))
    puts "💾 Knowledge base saved to #{@output_path}"
  end

  def output_summary(knowledge_base)
    puts "\n📊 Classification Summary:"
    puts "   Total files: #{knowledge_base[:total_files]}"
    puts "   High sensitivity files: #{knowledge_base[:high_sensitivity_files]}"
    puts "   High staleness files: #{knowledge_base[:high_staleness_files]}"
    puts "   High risk files: #{knowledge_base[:high_risk_files]}"
    puts "   Average confidence: #{knowledge_base[:avg_confidence]}"
    
    # Set GitHub Actions outputs
    if ENV['GITHUB_OUTPUT']
      File.open(ENV['GITHUB_OUTPUT'], 'a') do |f|
        f.puts "knowledge-base-path=#{@output_path}"
        f.puts "classified-files-count=#{knowledge_base[:total_files]}"
        f.puts "high-sensitivity-files=#{knowledge_base[:high_sensitivity_files]}"
      end
    else
      # Fallback for older versions or local testing
      puts "::set-output name=knowledge-base-path::#{@output_path}"
      puts "::set-output name=classified-files-count::#{knowledge_base[:total_files]}"
      puts "::set-output name=high-sensitivity-files::#{knowledge_base[:high_sensitivity_files]}"
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
    request['User-Agent'] = 'GitHub-Action-Docs-Classifier'
    
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
      max_tokens: 4000,
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
    
    opts.on("--repository REPO", "Repository to classify (org/name)") do |repo|
      options[:repository] = repo
    end
    
    opts.on("--output-path PATH", "Output path for knowledge base") do |path|
      options[:output_path] = path
    end
    
    opts.on("--docs-patterns PATTERNS", "Newline-separated file patterns to include") do |patterns|
      options[:docs_patterns] = patterns
    end
    
    opts.on("--exclude-patterns PATTERNS", "Newline-separated file patterns to exclude") do |patterns|
      options[:exclude_patterns] = patterns
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  begin
    classifier = RepositoryDocumentationClassifier.new(options)
    classifier.classify_repository
  rescue => e
    puts "❌ Error: #{e.message}"
    exit 1
  end
end
