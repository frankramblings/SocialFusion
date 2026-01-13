#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = './SocialFusion.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'SocialFusion' }

if target.nil?
  puts "ERROR: SocialFusion target not found!"
  exit 1
end

puts "Adding Autocomplete Provider files to project...\n"

# Find or create the Services/Autocomplete group
services_group = project.main_group.find_subpath('SocialFusion/Services', false)

if services_group.nil?
  puts "ERROR: Services group not found!"
  exit 1
end

# Check if Autocomplete subgroup exists, create if not
autocomplete_group = services_group.children.find { |child| child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.name == 'Autocomplete' }

if autocomplete_group.nil?
  puts "Creating Autocomplete group..."
  autocomplete_group = services_group.new_group('Autocomplete')
end

# Files to add
files_to_add = [
  'SocialFusion/Services/Autocomplete/SuggestionProvider.swift',
  'SocialFusion/Services/Autocomplete/TimelineContextProvider.swift',
  'SocialFusion/Services/Autocomplete/UnifiedTimelineContextProvider.swift',
  'SocialFusion/Services/Autocomplete/LocalHistoryProvider.swift',
  'SocialFusion/Services/Autocomplete/TimelineContextSuggestionProvider.swift',
  'SocialFusion/Services/Autocomplete/NetworkSuggestionProvider.swift',
  'SocialFusion/Services/Autocomplete/AutocompleteRanker.swift'
]

# Also add TimelineContext.swift to Models
models_group = project.main_group.find_subpath('SocialFusion/Models', false)
if models_group.nil?
  puts "ERROR: Models group not found!"
  exit 1
end

files_added = 0

# Add Autocomplete files
files_to_add.each do |file_path|
  file_name = File.basename(file_path)
  # Path should be relative to the Autocomplete group (just the filename)
  # Since the group is already in Services/Autocomplete, we just use the filename
  relative_path = file_name
  
  # Check if file already exists in project
  existing_ref = autocomplete_group.files.find { |f| f.path == file_name || f.path&.end_with?(file_name) }
  
  if existing_ref
    # Fix path if it's wrong (should be just filename, not full path)
    current_path = existing_ref.path || ""
    if current_path != relative_path && current_path.include?("Services/Autocomplete/")
      existing_ref.path = relative_path
      puts "  ✓ Fixed path for #{file_name} from '#{current_path}' to '#{relative_path}'"
    elsif current_path == relative_path
      puts "  ✓ #{file_name} already correct, skipping..."
    else
      puts "  ✓ #{file_name} already in project, skipping..."
    end
  else
    file_ref = autocomplete_group.new_reference(relative_path)
    file_ref.set_source_tree('<group>')
    target.source_build_phase.add_file_reference(file_ref)
    puts "  ✓ Added #{file_name} with path #{relative_path}"
    files_added += 1
  end
end

# Add TimelineContext.swift to Models
timeline_context_name = 'TimelineContext.swift'
existing_timeline_ref = models_group.files.find { |f| f.path == timeline_context_name }

if existing_timeline_ref
  puts "  ✓ #{timeline_context_name} already in project, skipping..."
else
  timeline_context_ref = models_group.new_reference(timeline_context_name)
  timeline_context_ref.set_source_tree('<group>')
  target.source_build_phase.add_file_reference(timeline_context_ref)
  puts "  ✓ Added #{timeline_context_name}"
  files_added += 1
end

# Save the project
project.save
puts "\n✓ Project saved successfully!"
puts "✓ Added #{files_added} new file(s) to project"

# Verify files exist
puts "\nVerifying files exist..."
all_files = files_to_add + ['SocialFusion/Models/TimelineContext.swift']
all_files.each do |file_path|
  if File.exist?(file_path)
    puts "  ✓ #{file_path}"
  else
    puts "  ⚠ WARNING: #{file_path} not found!"
  end
end

puts "\nDone! You can now build the project."
