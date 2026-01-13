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

puts "Fixing file paths for Muscle Memory Composer files...\n"

# Files to fix with their correct paths
files_to_fix = [
  { name: 'OffsetMapper.swift', group: 'SocialFusion/Utilities', correct_path: 'OffsetMapper.swift' },
  { name: 'TokenExtractor.swift', group: 'SocialFusion/Utilities', correct_path: 'TokenExtractor.swift' },
  { name: 'ComposerTextModel.swift', group: 'SocialFusion/Models', correct_path: 'ComposerTextModel.swift' },
  { name: 'AutocompleteToken.swift', group: 'SocialFusion/Models', correct_path: 'AutocompleteToken.swift' },
  { name: 'AutocompleteSuggestion.swift', group: 'SocialFusion/Models', correct_path: 'AutocompleteSuggestion.swift' },
  { name: 'AutocompleteService.swift', group: 'SocialFusion/Services', correct_path: 'AutocompleteService.swift' },
  { name: 'EmojiService.swift', group: 'SocialFusion/Services', correct_path: 'EmojiService.swift' },
  { name: 'AutocompleteCache.swift', group: 'SocialFusion/Stores', correct_path: 'AutocompleteCache.swift' },
  { name: 'AutocompleteOverlay.swift', group: 'SocialFusion/Views/Components', correct_path: 'AutocompleteOverlay.swift' },
  { name: 'ContentWarningEditor.swift', group: 'SocialFusion/Views/Components', correct_path: 'ContentWarningEditor.swift' },
  { name: 'BlueskyLabelsPicker.swift', group: 'SocialFusion/Views/Components', correct_path: 'BlueskyLabelsPicker.swift' },
  { name: 'PlatformConflictBanner.swift', group: 'SocialFusion/Views/Components', correct_path: 'PlatformConflictBanner.swift' }
]

fixed_count = 0

files_to_fix.each do |file_info|
  # Find the group
  group = project.main_group.find_subpath(file_info[:group], false)
  
  if group.nil?
    puts "⚠  Group not found: #{file_info[:group]}"
    next
  end
  
  # Find the file reference
  file_ref = group.files.find { |f| f.name == file_info[:name] || f.path == file_info[:name] }
  
  if file_ref.nil?
    puts "⚠  File reference not found: #{file_info[:name]}"
    next
  end
  
  # Check if path needs fixing
  current_path = file_ref.path || file_ref.name
  if current_path != file_info[:correct_path] && current_path.include?('SocialFusion/')
    puts "🔧 Fixing #{file_info[:name]}: #{current_path} -> #{file_info[:correct_path]}"
    file_ref.path = file_info[:correct_path]
    file_ref.set_source_tree('<group>')
    fixed_count += 1
  else
    puts "✓ #{file_info[:name]} path is correct"
  end
end

# Save the project
project.save
puts "\n✓ Project saved successfully!"
puts "Fixed #{fixed_count} file paths"
