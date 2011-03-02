#!/bin/bash
# Below are required environment variables with some example content:
# XCODE_BUILD_COMMAND='xcodebuild -sdk iphoneos4.1 -alltargets -configuration "Ad Hoc" clean build'
# XCODE_BUILD_CONFIGURATION='Ad Hoc'
# DISTRIBUTION_CERTIFICATE='iPhone Distribution: Handprint Corporation'
# PROVISIONING_PROFILE_PATH='/Users/tomcat/Library/MobileDevice/Provisioning Profiles/Your_Company_Ad_Hoc.mobileprovision'
# HG_BINARY='/usr/local/bin/hg'
# REMOTE_HOST='your.remote.host.com'
# REMOTE_PARENT_PATH='/www/docs/ios_builds'
# MANIFEST_SCRIPT_LOCATION='https://github.com/jharlap/ios-build-scripts/raw/master/generate_manifest.py'
# ROOT_DEPLOYMENT_ADDRESS='http://your.remote.host.com/ios_builds'
# ARCHIVE_FILENAME='beta_archive.zip'
# KEYCHAIN_LOCATION='/Users/tomcat/Library/Keychains/Your Company.keychain'
# KEYCHAIN_PASSWORD='Password'
# SSH_ARGS='-i /Users/jharlap/.ssh/id_rsa_keyless'

# Build project
#security default-keychain -s "$KEYCHAIN_LOCATION"
#security unlock-keychain -p $KEYCHAIN_PASSWORD "$KEYCHAIN_LOCATION"
eval $XCODE_BUILD_COMMAND

HG_HASH="$($HG_BINARY identify -n)-$($HG_BINARY identify -i)"
HG_HASH=${HG_HASH//[[:space:]]}
HG_HASH=${HG_HASH//+}
BUILD_CHANGES="$($HG_BINARY log -r tip)"
BUILD_DIRECTORY="$(pwd)/build/${XCODE_BUILD_CONFIGURATION}-iphoneos"
cd "$BUILD_DIRECTORY" || die "Build directory does not exist."
MANIFEST_SCRIPT=$(curl -fsS $MANIFEST_SCRIPT_LOCATION)
MANIFEST_OUTPUT_HTML_FILENAME='index.html'
MANIFEST_OUTPUT_MANIFEST_FILENAME='manifest.plist'
for APP_FILENAME in *.app; do
	APP_NAME=$(echo "$APP_FILENAME" | sed -e 's/.app//')
	IPA_FILENAME="$APP_NAME.ipa"
	DSYM_FILEPATH="$APP_FILENAME.dSYM"

	/usr/bin/xcrun -sdk iphoneos PackageApplication -v "$APP_FILENAME" -o "$BUILD_DIRECTORY/$IPA_FILENAME" --sign "$DISTRIBUTION_CERTIFICATE" --embed "$PROVISIONING_PROFILE_PATH"

	# Create legacy archive for pre iOS4.0 users
	cp "$PROVISIONING_PROFILE_PATH" .
	PROVISIONING_PROFILE_FILENAME=$(basename "$PROVISIONING_PROFILE_PATH")
	zip "$ARCHIVE_FILENAME" "$IPA_FILENAME" "$PROVISIONING_PROFILE_FILENAME"
	rm "$PROVISIONING_PROFILE_FILENAME"

	# Output of this is index.html and manifest.plist
	python -c "$MANIFEST_SCRIPT" -f "$APP_FILENAME" -d "$ROOT_DEPLOYMENT_ADDRESS/$HG_HASH/$MANIFEST_OUTPUT_MANIFEST_FILENAME" -a "$ARCHIVE_FILENAME" -c "$BUILD_CHANGES"

	# Create tarball with .ipa, dSYM directory, legacy build and generated manifest files and scp them all across
	PAYLOAD_FILENAME='payload.tar'
	tar -cf $PAYLOAD_FILENAME "$IPA_FILENAME" "$DSYM_FILEPATH" "$ARCHIVE_FILENAME" "$MANIFEST_OUTPUT_HTML_FILENAME" "$MANIFEST_OUTPUT_MANIFEST_FILENAME"

	QUOTE='"'
	ssh $SSH_ARGS $REMOTE_HOST "cd $REMOTE_PARENT_PATH; rm -rf ${QUOTE}$APP_NAME${QUOTE}/$HG_HASH; mkdir -p ${QUOTE}$APP_NAME${QUOTE}/$HG_HASH;"
	scp $SSH_ARGS "$PAYLOAD_FILENAME" "$REMOTE_HOST:$REMOTE_PARENT_PATH/${QUOTE}$APP_NAME${QUOTE}/$HG_HASH"
	ssh $SSH_ARGS $REMOTE_HOST "cd $REMOTE_PARENT_PATH/${QUOTE}$APP_NAME${QUOTE}/$HG_HASH; tar -xf $PAYLOAD_FILENAME; rm $PAYLOAD_FILENAME; rm -f $REMOTE_PARENT_PATH/${QUOTE}$APP_NAME${QUOTE}/latest; ln -s $REMOTE_PARENT_PATH/${QUOTE}$APP_NAME${QUOTE}/$HG_HASH $REMOTE_PARENT_PATH/${QUOTE}$APP_NAME${QUOTE}/latest"

	# Clean up
	rm "$IPA_FILENAME"
	rm "$ARCHIVE_FILENAME"
	rm "$MANIFEST_OUTPUT_HTML_FILENAME"
	rm "$MANIFEST_OUTPUT_MANIFEST_FILENAME"
	rm "$PAYLOAD_FILENAME"
done
