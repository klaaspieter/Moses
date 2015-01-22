namespace :test do
  task :default do
    sh "xcodebuild -workspace Moses.xcworkspace -scheme Moses -sdk iphonesimulator test | xcpretty -ct"
  end

  task :ci do
    sh "xcodebuild -workspace Moses.xcworkspace -scheme Moses -sdk iphonesimulator test"
  end
end

task :test => "test:default"
task :default => "test"
