require 'xcodeproj'

project_path = 'NotchPulse.xcodeproj'
project = Xcodeproj::Project.open(project_path)

main_group = project.main_group.groups.find { |g| g.name == 'NotchPulse' || g.path == 'NotchPulse' }
managers_group = main_group.groups.find { |g| g.name == 'managers' || g.path == 'managers' }
face_id_core_group = managers_group.groups.find { |g| g.name == 'FaceIDCore' || g.path == 'FaceIDCore' }
overlay_group = face_id_core_group.groups.find { |g| g.name == 'Overlay' }

if overlay_group
  overlay_group.set_path('Overlay')
  project.save
  puts "Set path of Overlay group to 'Overlay'"
else
  puts "Overlay group not found"
end
