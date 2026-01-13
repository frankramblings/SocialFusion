#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = './SocialFusion.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'SocialFusion' }

puts "Adding ShareAsImage files to project..."

# Find or create the ShareAsImage group
share_as_image_group = project.main_group.find_subpath('SocialFusion/ShareAsImage', false)

if share_as_image_group.nil?
  puts "ShareAsImage group not found, creating it..."
  social_fusion_group = project.main_group.find_subpath('SocialFusion', false)
  if social_fusion_group
    share_as_image_group = social_fusion_group.new_group('ShareAsImage')
  else
    puts "ERROR: SocialFusion group not found!"
    exit 1
  end
end

# Find or create DomainAdapters subgroup
domain_adapters_group = share_as_image_group.find_subpath('DomainAdapters', false)
if domain_adapters_group.nil?
  domain_adapters_group = share_as_image_group.new_group('DomainAdapters')
end

# List of files to add
files_to_add = [
  'SocialFusion/ShareAsImage/ShareRenderModels.swift',
  'SocialFusion/ShareAsImage/ThreadSlicer.swift',
  'SocialFusion/ShareAsImage/ShareThreadRenderBuilder.swift',
  'SocialFusion/ShareAsImage/ShareImageViews.swift',
  'SocialFusion/ShareAsImage/ShareImageRenderer.swift',
  'SocialFusion/ShareAsImage/ShareAsImageViewModel.swift',
  'SocialFusion/ShareAsImage/ShareAsImageSheet.swift',
  'SocialFusion/ShareAsImage/ShareAsImageCoordinator.swift',
  'SocialFusion/ShareAsImage/ShareImagePreloader.swift',
  'SocialFusion/ShareAsImage/ShareSynchronousImageView.swift',
  'SocialFusion/ShareAsImage/DomainAdapters/UnifiedAdapter.swift'
]

# Check existing files
existing_files = share_as_image_group.files.map(&:path)
existing_domain_files = domain_adapters_group.files.map(&:path)

files_to_add.each do |file_path|
  file_name = File.basename(file_path)
  relative_path = file_path.sub('SocialFusion/', '')
  
  # Determine which group to add to
  if file_path.include?('DomainAdapters')
    group = domain_adapters_group
    existing = existing_domain_files
  else
    group = share_as_image_group
    existing = existing_files
  end
  
  # Check if file already exists in project
  unless existing.include?(file_name) || existing.include?(relative_path)
    file_ref = group.new_reference(relative_path)
    file_ref.set_source_tree('<group>')
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{file_name} to project"
  else
    puts "Skipped #{file_name} (already in project)"
  end
end

# Save the project
project.save
puts "Project saved successfully!"

# Verify files exist
puts "\nVerifying files exist..."
files_to_add.each do |file_path|
  if File.exist?(file_path)
    puts "✓ #{File.basename(file_path)} exists"
  else
    puts "✗ #{File.basename(file_path)} NOT FOUND at: #{file_path}"
  end
end
