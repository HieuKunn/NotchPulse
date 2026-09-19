require 'xcodeproj'

project_path = 'NotchPulse.xcodeproj'
project = Xcodeproj::Project.open(project_path)

def find_or_create_group(parent, group_name)
  parent.groups.find { |g| g.name == group_name || g.path == group_name } || parent.new_group(group_name)
end

main_group = project.main_group.groups.find { |g| g.name == 'NotchPulse' || g.path == 'NotchPulse' }
managers_group = find_or_create_group(main_group, 'managers')
face_id_core_group = find_or_create_group(managers_group, 'FaceIDCore')
overlay_group = find_or_create_group(face_id_core_group, 'Overlay')

target = project.targets.first

Dir.glob('NotchPulse/managers/FaceIDCore/Overlay/*.swift').each do |file_path|
  file_name = File.basename(file_path)
  unless overlay_group.files.any? { |f| f.name == file_name || f.path == file_name }
    # Set the actual physical path relative to the group
    file_ref = overlay_group.new_file(file_name)
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{file_name} to project"
  else
    puts "#{file_name} already in project"
  end
end

project.save
puts "Project saved."
