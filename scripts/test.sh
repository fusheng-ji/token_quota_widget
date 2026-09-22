#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
derived_data="${BEAVERMETER_DERIVED_DATA:-/tmp/beavermeter-derived}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export BEAVERMETER_BUNDLE_PREFIX="${BEAVERMETER_BUNDLE_PREFIX:-com.beavermeter.tests}"
cd "$project_dir"

for script in scripts/*.sh scripts/lib/*.sh Tests/*.sh Tests/Support/*.sh; do
  zsh -n "$script"
done
python3 -B -m unittest discover -s Tests -p '*_test.py'
zsh Tests/migration_test.sh
zsh Tests/install_test.sh
xcodegen generate
xcodebuild -project BeaverMeter.xcodeproj -scheme BeaverMeter \
  -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES ARCHS="$(uname -m)" test
zsh Tests/collector_test.sh "$derived_data/Build/Products/Debug/BeaverMeterCollector"
print "All BeaverMeter tests passed."
