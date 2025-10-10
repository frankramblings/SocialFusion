#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = './SocialFusion.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'SocialFusion' }

# Find files with incorrect paths and remove them
files_to_remove = []
project.main_group.recursive_children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
    if child.path && (child.path.include?('SocialFusion/Services/MediaErrorHandler.swift') || 
                      child.path.include?('SocialFusion/Services/MediaMemoryManager.swift'))
      if child.path.include?('SocialFusion/Services/SocialFusion/Services/')
        files_to_remove << child
        puts "Found incorrect path: #{child.path}"
      end
    end
  end
end

# Remove files with incorrect paths
files_to_remove.each do |file_ref|
  # Remove from build phases
  target.source_build_phase.files.each do |build_file|
    if build_file.file_ref == file_ref
      target.source_build_phase.files.delete(build_file)
      puts "Removed from build phase: #{file_ref.path}"
    end
  end
  
  # Remove from project
  file_ref.remove_from_project
  puts "Removed file reference: #{file_ref.path}"
end

# Find the Services group
services_group = project.main_group.find_subpath('SocialFusion/Services', false)

if services_group
  # Add the files with correct paths
  unless services_group.children.any? { |child| child.path == 'MediaErrorHandler.swift' }
    file_ref = services_group.new_reference('MediaErrorHandler.swift')
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added MediaErrorHandler.swift with correct path"
  end

  unless services_group.children.any? { |child| child.path == 'MediaMemoryManager.swift' }
    file_ref = services_group.new_reference('MediaMemoryManager.swift')
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added MediaMemoryManager.swift with correct path"
  end
else
  puts "Services group not found"
end

# Save the project
project.save
puts "Project saved successfully"

