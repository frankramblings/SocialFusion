#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = './SocialFusion.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'SocialFusion' }

puts "Adding new media services files to project..."

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

# Add MediaPerformanceMonitor.swift
performance_monitor_ref = services_group.new_reference('MediaPerformanceMonitor.swift')
performance_monitor_ref.set_source_tree('<group>')
target.source_build_phase.add_file_reference(performance_monitor_ref)
puts "Added MediaPerformanceMonitor.swift"

# Find or create the test target
test_target = project.targets.find { |t| t.name == 'SocialFusionTests' }

if test_target.nil?
  puts "Creating SocialFusionTests target..."
  test_target = project.new_target(:unit_test_bundle, 'SocialFusionTests', :ios, '16.0')
  test_target.add_dependency(target)
end

# Find or create the SocialFusionTests group
tests_group = project.main_group.find_subpath('SocialFusionTests', false)

if tests_group.nil?
  puts "Creating SocialFusionTests group..."
  tests_group = project.main_group.new_group('SocialFusionTests')
end

# Add MediaRobustnessTests.swift
tests_ref = tests_group.new_reference('MediaRobustnessTests.swift')
tests_ref.set_source_tree('<group>')
test_target.source_build_phase.add_file_reference(tests_ref)
puts "Added MediaRobustnessTests.swift to test target"

# Save the project
project.save
puts "Project saved successfully!"

# Verify the files exist
puts "Verifying files exist..."
performance_monitor_path = File.join(Dir.pwd, 'SocialFusion/Services/MediaPerformanceMonitor.swift')
tests_path = File.join(Dir.pwd, 'SocialFusionTests/MediaRobustnessTests.swift')

if File.exist?(performance_monitor_path)
  puts "✓ MediaPerformanceMonitor.swift exists at: #{performance_monitor_path}"
else
  puts "✗ MediaPerformanceMonitor.swift NOT FOUND at: #{performance_monitor_path}"
end

if File.exist?(tests_path)
  puts "✓ MediaRobustnessTests.swift exists at: #{tests_path}"
else
  puts "✗ MediaRobustnessTests.swift NOT FOUND at: #{tests_path}"
end

