#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = './SocialFusion.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'SocialFusion' }

# Find the Services group (or create it if it doesn't exist)
services_group = project.main_group.find_subpath('SocialFusion/Services', true)

# Add the media service files
media_error_handler_path = 'SocialFusion/Services/MediaErrorHandler.swift'
media_memory_manager_path = 'SocialFusion/Services/MediaMemoryManager.swift'

# Check if files already exist in project
existing_files = services_group.files.map(&:path)

unless existing_files.include?('MediaErrorHandler.swift')
  file_ref = services_group.new_reference(media_error_handler_path)
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added MediaErrorHandler.swift to project"
end

unless existing_files.include?('MediaMemoryManager.swift')
  file_ref = services_group.new_reference(media_memory_manager_path)
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added MediaMemoryManager.swift to project"
end

# Save the project
project.save
puts "Project saved successfully"

