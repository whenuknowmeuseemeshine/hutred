# Добавляет в Xcode-проект виджет (HutredWidget) — запускается в сборке
# на GitHub перед flutter build ios. Повторный запуск ничего не ломает.
require 'xcodeproj'

proj = Xcodeproj::Project.open(File.join(__dir__, '..', 'Runner.xcodeproj'))
if proj.targets.any? { |t| t.name == 'HutredWidget' }
  puts 'HutredWidget уже есть'
  exit 0
end

runner = proj.targets.find { |t| t.name == 'Runner' }
ext = proj.new_target(:app_extension, 'HutredWidget', :ios, '17.0', nil, :swift)

widget_group = proj.main_group.find_subpath('HutredWidget', true)
widget_group.set_source_tree('<group>')
widget_group.set_path('HutredWidget')
widget_src = widget_group.new_reference('HutredWidget.swift')
widget_group.new_reference('Info.plist')
widget_group.new_reference('HutredWidget.entitlements')

shared_group = proj.main_group.find_subpath('Shared', true)
shared_group.set_source_tree('<group>')
shared_group.set_path('Shared')
shared_src = shared_group.new_reference('WidgetShared.swift')

proj.main_group.find_subpath('Runner', false)&.new_reference('Runner.entitlements')

ext.add_file_references([widget_src, shared_src])
runner.add_file_references([shared_src])
%w[WidgetKit SwiftUI AppIntents].each { |f| ext.add_system_framework(f) }

ext.build_configurations.each do |c|
  bs = c.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'ru.hutred.hutred.HutredWidget'
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE'] = 'HutredWidget/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'HutredWidget/HutredWidget.entitlements'
  bs['SWIFT_VERSION'] = '5.0'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['SKIP_INSTALL'] = 'YES'
  bs['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  bs['ENABLE_BITCODE'] = 'NO'
  # Версия как у приложения (FLUTTER_BUILD_NAME/NUMBER из Generated.xcconfig).
  rc = runner.build_configurations.find { |r| r.name == c.name } ||
       runner.build_configurations.find { |r| r.name == 'Release' }
  c.base_configuration_reference = rc.base_configuration_reference if rc
end

# Сборка Profile у Flutter тоже есть — добавляем её виджету.
if runner.build_configurations.any? { |c| c.name == 'Profile' } &&
   ext.build_configurations.none? { |c| c.name == 'Profile' }
  rel = ext.build_configurations.find { |c| c.name == 'Release' }
  prof = proj.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  prof.name = 'Profile'
  prof.build_settings = rel.build_settings.dup
  prof.base_configuration_reference =
    runner.build_configurations.find { |c| c.name == 'Profile' }.base_configuration_reference
  ext.build_configuration_list.build_configurations << prof
end

runner.build_configurations.each do |c|
  bs = c.build_settings
  bs['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  # AppIntents/WidgetKit есть не на всех iOS — подключаем «мягко».
  flags = Array(bs['OTHER_LDFLAGS'] || '$(inherited)')
  flags += ['-weak_framework', 'AppIntents', '-weak_framework', 'WidgetKit']
  bs['OTHER_LDFLAGS'] = flags
end

runner.add_dependency(ext)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Встраивание виджета — сразу после «Embed Frameworks», до скриптов Flutter,
# иначе Xcode находит цикл в сборке.
phases = runner.build_phases
phases.delete(embed)
idx = phases.index { |p| p.respond_to?(:name) && p.name == 'Embed Frameworks' } ||
      phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) } ||
      (phases.size - 1)
phases.insert(idx + 1, embed)

proj.save
puts 'HutredWidget добавлен'
