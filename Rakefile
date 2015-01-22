task :test do
  sh "set -o pipefail && xcodebuild -workspace Moses.xcworkspace -scheme Moses -sdk iphonesimulator test | xcpretty -ct"
end

task :default => :test
