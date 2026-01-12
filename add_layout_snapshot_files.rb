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

puts "Adding layout snapshot system files to project..."

# Find Models group
models_group = project.main_group.find_subpath('SocialFusion/Models', false)
if models_group.nil?
  puts "ERROR: Models group not found!"
  exit 1
end

# Find Utilities group
utilities_group = project.main_group.find_subpath('SocialFusion/Utilities', false)
if utilities_group.nil?
  puts "ERROR: Utilities group not found!"
  exit 1
end

# Find Views/Components group
components_group = project.main_group.find_subpath('SocialFusion/Views/Components', false)
if components_group.nil?
  puts "ERROR: Views/Components group not found!"
  exit 1
end

# Files to add
files_to_add = [
  { group: models_group, name: 'PostLayoutSnapshot.swift' },
  { group: utilities_group, name: 'MediaDimensionCache.swift' },
  { group: utilities_group, name: 'ImageSizeFetcher.swift' },
  { group: utilities_group, name: 'MediaPrefetcher.swift' },
  { group: utilities_group, name: 'PostLayoutSnapshotBuilder.swift' },
  { group: utilities_group, name: 'FeedUpdateCoordinator.swift' },
  { group: components_group, name: 'MediaContainerView.swift' }
]

files_to_add.each do |file_info|
  group = file_info[:group]
  name = file_info[:name]
  
  # Check if file already exists in project
  existing_files = group.files.map(&:path)
  
  if existing_files.include?(name)
    puts "  #{name} already exists in project, skipping..."
  else
    # Add the file reference
    file_ref = group.new_reference(name)
    file_ref.set_source_tree('<group>')
    
    # Add to build phase
    target.source_build_phase.add_file_reference(file_ref)
    
    puts "  ✓ Added #{name} to project"
  end
end

# Save the project
project.save
puts "\n✓ Project saved successfully!"

# Verify files exist
puts "\nVerifying files exist..."
files_to_add.each do |file_info|
  name = file_info[:name]
  group_path = file_info[:group].path || file_info[:group].name
  file_path = File.join(Dir.pwd, 'SocialFusion', group_path, name)
  if File.exist?(file_path)
    puts "  ✓ #{name} exists"
  else
    puts "  ⚠ WARNING: #{name} not found at: #{file_path}"
  end
end

puts "\nDone! You can now build the project."
