# fastlane 项目内依赖（不污染全局 ruby）
# 用法：bundle install --path vendor/bundle 后 bundle exec fastlane ...
# bootstrap_fastlane.sh 会自动跑这些。
source "https://rubygems.org"

gem "fastlane"
gem "cocoapods" if false # 如项目用 CocoaPods 再放开

# 由 bootstrap 生成/更新 Gemfile.lock 以锁定可复现版本
