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

puts "Adding FullscreenMediaView.swift to project..."

# Find the Views/Components group
components_group = project.main_group.find_subpath('SocialFusion/Views/Components', false)

if components_group.nil?
  puts "ERROR: Views/Components group not found!"
  exit 1
end

# Check if file already exists in project
existing_files = components_group.files.map(&:path)

if existing_files.include?('FullscreenMediaView.swift')
  puts "FullscreenMediaView.swift already exists in project, skipping..."
else
  # Add the file reference
  file_ref = components_group.new_reference('FullscreenMediaView.swift')
  file_ref.set_source_tree('<group>')
  
  # Add to build phase
  target.source_build_phase.add_file_reference(file_ref)
  
  puts "✓ Added FullscreenMediaView.swift to project"
end

# Save the project
project.save
puts "✓ Project saved successfully!"

# Verify the file exists
file_path = File.join(Dir.pwd, 'SocialFusion/Views/Components/FullscreenMediaView.swift')
if File.exist?(file_path)
  puts "✓ File exists at: #{file_path}"
else
  puts "⚠ WARNING: File not found at expected path: #{file_path}"
end

puts "\nDone! You can now build the project."

