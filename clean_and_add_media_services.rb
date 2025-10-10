#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = './SocialFusion.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'SocialFusion' }

puts "Cleaning up incorrect file references..."

# Remove ALL references to MediaErrorHandler and MediaMemoryManager first
files_to_remove = []
build_files_to_remove = []

# Find all file references with these names
project.main_group.recursive_children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
    if child.path && (child.path.include?('MediaErrorHandler.swift') || child.path.include?('MediaMemoryManager.swift'))
      files_to_remove << child
      puts "Found file reference to remove: #{child.path}"
    end
  end
end

# Remove from build phases first
target.source_build_phase.files.each do |build_file|
  if build_file.file_ref && files_to_remove.include?(build_file.file_ref)
    build_files_to_remove << build_file
    puts "Will remove from build phase: #{build_file.file_ref.path}"
  end
end

# Remove build file references
build_files_to_remove.each do |build_file|
  target.source_build_phase.files.delete(build_file)
  puts "Removed from build phase"
end

# Remove file references
files_to_remove.each do |file_ref|
  file_ref.remove_from_project
  puts "Removed file reference"
end

# Now add them correctly
puts "Adding files with correct paths..."

# Find or create the Services group
services_group = project.main_group.find_subpath('SocialFusion/Services', false)

if services_group.nil?
  puts "Services group not found, creating it..."
  social_fusion_group = project.main_group.find_subpath('SocialFusion', false)
  if social_fusion_group
    services_group = social_fusion_group.new_group('Services')
  else
    puts "ERROR: SocialFusion group not found!"
    exit 1
  end
end

# Add MediaErrorHandler.swift
error_handler_ref = services_group.new_reference('MediaErrorHandler.swift')
error_handler_ref.set_source_tree('<group>')
target.source_build_phase.add_file_reference(error_handler_ref)
puts "Added MediaErrorHandler.swift"

# Add MediaMemoryManager.swift  
memory_manager_ref = services_group.new_reference('MediaMemoryManager.swift')
memory_manager_ref.set_source_tree('<group>')
target.source_build_phase.add_file_reference(memory_manager_ref)
puts "Added MediaMemoryManager.swift"

# Save the project
project.save
puts "Project saved successfully!"

# Verify the files exist
puts "Verifying files exist..."
error_handler_path = File.join(Dir.pwd, 'SocialFusion/Services/MediaErrorHandler.swift')
memory_manager_path = File.join(Dir.pwd, 'SocialFusion/Services/MediaMemoryManager.swift')

if File.exist?(error_handler_path)
  puts "✓ MediaErrorHandler.swift exists at: #{error_handler_path}"
else
  puts "✗ MediaErrorHandler.swift NOT FOUND at: #{error_handler_path}"
end

if File.exist?(memory_manager_path)
  puts "✓ MediaMemoryManager.swift exists at: #{memory_manager_path}"
else
  puts "✗ MediaMemoryManager.swift NOT FOUND at: #{memory_manager_path}"
end

