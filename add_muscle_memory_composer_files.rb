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

puts "Adding Muscle Memory Composer feature files to project...\n"

# Files to add with their group paths
files_to_add = [
  {
    path: 'SocialFusion/Utilities/OffsetMapper.swift',
    group_path: 'SocialFusion/Utilities',
    name: 'OffsetMapper.swift'
  },
  {
    path: 'SocialFusion/Utilities/TokenExtractor.swift',
    group_path: 'SocialFusion/Utilities',
    name: 'TokenExtractor.swift'
  },
  {
    path: 'SocialFusion/Models/ComposerTextModel.swift',
    group_path: 'SocialFusion/Models',
    name: 'ComposerTextModel.swift'
  },
  {
    path: 'SocialFusion/Models/AutocompleteToken.swift',
    group_path: 'SocialFusion/Models',
    name: 'AutocompleteToken.swift'
  },
  {
    path: 'SocialFusion/Models/AutocompleteSuggestion.swift',
    group_path: 'SocialFusion/Models',
    name: 'AutocompleteSuggestion.swift'
  },
  {
    path: 'SocialFusion/Services/AutocompleteService.swift',
    group_path: 'SocialFusion/Services',
    name: 'AutocompleteService.swift'
  },
  {
    path: 'SocialFusion/Services/EmojiService.swift',
    group_path: 'SocialFusion/Services',
    name: 'EmojiService.swift'
  },
  {
    path: 'SocialFusion/Stores/AutocompleteCache.swift',
    group_path: 'SocialFusion/Stores',
    name: 'AutocompleteCache.swift'
  },
  {
    path: 'SocialFusion/Views/Components/AutocompleteOverlay.swift',
    group_path: 'SocialFusion/Views/Components',
    name: 'AutocompleteOverlay.swift'
  },
  {
    path: 'SocialFusion/Views/Components/ContentWarningEditor.swift',
    group_path: 'SocialFusion/Views/Components',
    name: 'ContentWarningEditor.swift'
  },
  {
    path: 'SocialFusion/Views/Components/BlueskyLabelsPicker.swift',
    group_path: 'SocialFusion/Views/Components',
    name: 'BlueskyLabelsPicker.swift'
  },
  {
    path: 'SocialFusion/Views/Components/PlatformConflictBanner.swift',
    group_path: 'SocialFusion/Views/Components',
    name: 'PlatformConflictBanner.swift'
  }
]

added_count = 0
skipped_count = 0

files_to_add.each do |file_info|
  # Find or create the group
  group = project.main_group.find_subpath(file_info[:group_path], true)
  
  if group.nil?
    puts "ERROR: Could not find or create group: #{file_info[:group_path]}"
    next
  end
  
  # Check if file already exists in project
  existing_files = group.files.map { |f| f.path || f.name }
  file_name = file_info[:name]
  
  if existing_files.include?(file_name) || existing_files.include?(file_info[:path])
    puts "⏭  Skipping #{file_name} (already in project)"
    skipped_count += 1
    next
  end
  
  # Verify file exists on disk
  file_path = File.join(Dir.pwd, file_info[:path])
  unless File.exist?(file_path)
    puts "⚠  WARNING: File not found at #{file_path}, skipping..."
    skipped_count += 1
    next
  end
  
  # Add the file reference (use just the filename since we're already in the correct group)
  file_ref = group.new_reference(file_name)
  file_ref.set_source_tree('<group>')
  
  # Add to build phase
  target.source_build_phase.add_file_reference(file_ref)
  
  puts "✓ Added #{file_name}"
  added_count += 1
end

# Save the project
project.save
puts "\n✓ Project saved successfully!"
puts "\nSummary:"
puts "  Added: #{added_count} files"
puts "  Skipped: #{skipped_count} files"

if added_count > 0
  puts "\n✓ Done! You can now build the project."
else
  puts "\n⚠ No new files were added. All files may already be in the project."
end
