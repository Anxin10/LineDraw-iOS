require 'xcodeproj'
root=File.expand_path('..',__dir__)
project=Xcodeproj::Project.new(File.join(root,'LineDraw.xcodeproj'))
app=project.new_target(:application,'LineDraw',:ios,'27.0')
app.product_name='LineDraw'
group=project.main_group.new_group('App','App')
Dir.glob(File.join(root,'App','*.swift')).sort.each{|p|app.source_build_phase.add_file_reference(group.new_file(File.basename(p)))}
resources=project.main_group.new_group('Resources','Resources')
app.resources_build_phase.add_file_reference(resources.new_file('Assets.xcassets'))
# Private local builds can prepare a compatible DDI from installed Xcode once.
# The .runtime folder and Apple payloads are excluded from source distributions.
ddi_source='/Library/Developer/DeveloperDiskImages/iOS_DDI/Restore'
ddi_output=File.join(root,'.runtime','BundledDDI')
if File.exist?(File.join(ddi_source,'BuildManifest.plist'))
 require 'fileutils'
 FileUtils.rm_rf(ddi_output)
 abort 'DDI preparation failed' unless system('python3',File.join(root,'scripts','prepare-device-ddi.py'),'--restore-dir',ddi_source,'--output',ddi_output)
 ref=project.main_group.new_file('.runtime/BundledDDI');ref.last_known_file_type='folder'
 app.resources_build_phase.add_file_reference(ref)
end

['THIRD_PARTY_NOTICES.txt','Rust-THIRD_PARTY_NOTICES.txt','LineDraw-LICENSE.txt'].each{|name|app.resources_build_phase.add_file_reference(resources.new_file(name))}
pkg=project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference);pkg.relative_path='Core';project.root_object.package_references<<pkg
product=project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency);product.product_name='LineDrawCore';product.package=pkg;app.package_product_dependencies<<product
buildfile=project.new(Xcodeproj::Project::Object::PBXBuildFile);buildfile.product_ref=product;app.frameworks_build_phase.files<<buildfile
app.build_configurations.each do |config|
 config.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'com.beybladehunter.linedraw.ios','SWIFT_VERSION'=>'5.0','GENERATE_INFOPLIST_FILE'=>'NO','INFOPLIST_FILE'=>'App/Info.plist','TARGETED_DEVICE_FAMILY'=>'1,2','CODE_SIGN_STYLE'=>'Automatic','MARKETING_VERSION'=>'1.1.0','CURRENT_PROJECT_VERSION'=>'16','ASSETCATALOG_COMPILER_APPICON_NAME'=>'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'=>'AccentColor','SWIFT_EMIT_LOC_STRINGS'=>'YES','SUPPORTS_MACCATALYST'=>'NO','ENABLE_USER_SCRIPT_SANDBOXING'=>'YES','EXCLUDED_ARCHS[sdk=iphonesimulator*]'=>'x86_64'})
 config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG $(inherited)' if config.name=='Debug'
end
# Live Activity keeps the one-time PIN readable while the user enters it in Settings.
shared=project.main_group.new_group('Shared','Shared')
attrs=shared.new_file('PairingActivityAttributes.swift');app.source_build_phase.add_file_reference(attrs)
widget=project.new_target(:app_extension,'PairingActivity',:ios,'27.0')
wg=project.main_group.new_group('PairingActivity','PairingActivity')
widget.source_build_phase.add_file_reference(wg.new_file('PairingActivity.swift'))
widget.source_build_phase.add_file_reference(attrs)
widget.build_configurations.each{|c|c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'com.beybladehunter.linedraw.ios.PairingActivity','SWIFT_VERSION'=>'5.0','GENERATE_INFOPLIST_FILE'=>'NO','INFOPLIST_FILE'=>'PairingActivity/Info.plist','TARGETED_DEVICE_FAMILY'=>'1,2','CODE_SIGN_STYLE'=>'Automatic','MARKETING_VERSION'=>'1.1.0','CURRENT_PROJECT_VERSION'=>'16','APPLICATION_EXTENSION_API_ONLY'=>'YES','SKIP_INSTALL'=>'YES','EXCLUDED_ARCHS[sdk=iphonesimulator*]'=>'x86_64'})}
app.add_dependency(widget)
embed=app.new_copy_files_build_phase('Embed App Extensions');embed.dst_subfolder_spec='13';embed.add_file_reference(widget.product_reference)
ui=project.new_target(:ui_test_bundle,'LineDrawUITests',:ios,'27.0');ui.add_dependency(app)
ug=project.main_group.new_group('UITests','UITests');Dir.glob(File.join(root,'UITests','*.swift')).sort.each{|p|ui.source_build_phase.add_file_reference(ug.new_file(File.basename(p)))}
ui.build_configurations.each{|c|c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'com.beybladehunter.linedraw.ios.uitests','SWIFT_VERSION'=>'5.0','GENERATE_INFOPLIST_FILE'=>'YES','EXCLUDED_ARCHS[sdk=iphonesimulator*]'=>'x86_64','TEST_TARGET_NAME'=>'LineDraw','CODE_SIGN_STYLE'=>'Automatic','TARGETED_DEVICE_FAMILY'=>'1,2'})}
bridge=project.main_group.new_file('.runtime/LineDrawDeviceBridge.xcframework')
app.frameworks_build_phase.add_file_reference(bridge)
app.add_system_framework('Security')
app.add_system_framework('SystemConfiguration')
app.add_system_framework('BackgroundTasks')
app.build_configurations.each{|c|c.build_settings['OTHER_LDFLAGS']='$(inherited) -lc++ -liconv -lresolv'}
project.save
scheme=Xcodeproj::XCScheme.new;scheme.add_build_target(app);scheme.add_test_target(ui);scheme.set_launch_target(app);scheme.save_as(project.path,'LineDraw',true)
puts project.path
