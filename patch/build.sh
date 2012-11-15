#!/bin/sh

# Build ReduceBrightness patch for a specific Logitech Media Server (Squeezebox) version.
# Run ./build.sh to build for fab4 (Touch) and baby (Radio)
# Run ./build.sh fab4 to only build for fab4 (Touch)
# Run ./build.sh baby to only build for baby (Radio)

# LMS version to build for
VERSION="7.8"
# Patch version
PATCH_VERSION="1.2"

# Build defaults
BUILD_FAB4=true
BUILD_BABY=true

if [ "$1" = "fab4" ]; then
	BUILD_FAB4=true
	BUILD_BABY=false
elif [ "$1" = "baby" ]; then
	BUILD_FAB4=false
	BUILD_BABY=true
fi

mkdir -p ReduceBrightness-$PATCH_VERSION
echo '*' > ReduceBrightness-$PATCH_VERSION/.gitignore

if [ $BUILD_FAB4 = true ]; then
	echo 'Building patch for Squeezebox Touch...'

	git diff upstream/$VERSION ../src/squeezeplay_fab4/share/applets/SqueezeboxFab4/* > ReduceBrightness-$PATCH_VERSION/ReduceBrightness-fab4-$PATCH_VERSION.patch

	cd ReduceBrightness-$PATCH_VERSION
	sed 's/--- a\/src\/squeezeplay_fab4\/share\//--- share\/jive\//g' ReduceBrightness-fab4-$PATCH_VERSION.patch > ReduceBrightness-fab4.patch.tmp
	mv ReduceBrightness-fab4.patch.tmp ReduceBrightness-fab4-$PATCH_VERSION.patch
	sed 's/+++ b\/src\/squeezeplay_fab4\/share\//+++ share\/jive\//g' ReduceBrightness-fab4-$PATCH_VERSION.patch > ReduceBrightness-fab4.patch.tmp
	mv ReduceBrightness-fab4.patch.tmp ReduceBrightness-fab4-$PATCH_VERSION.patch

	CHECKSUM=`sha1sum ReduceBrightness-fab4-$PATCH_VERSION.patch | awk '{print $1}'`

	# Copy base XML file to output directory
	cp ../repo.xml repo.xml
	
	# Replace placeholder with proper checksum
	sed 's/%CHECKSUM%/'${CHECKSUM}'/g' repo.xml > repo.xml.tmp
	mv repo.xml.tmp repo.xml
	
	# Replace placeholder with proper file name
	sed 's/%PATCH%/ReduceBrightness-fab4-'${PATCH_VERSION}'.patch/g' repo.xml > repo.xml.tmp
	mv repo.xml.tmp repo.xml

	# Replace version info
	sed 's/%VERSION%/'${VERSION}'/g' repo.xml > repo.xml.tmp
	mv repo.xml.tmp repo.xml
	sed 's/%PATCH_VERSION%/'${PATCH_VERSION}'/g' repo.xml > repo.xml.tmp
	mv repo.xml.tmp repo.xml
	cd ..
fi

if [ $BUILD_BABY = true ]; then
	echo 'Building patch for Squeezebox Radio...'
	git diff upstream/$VERSION ../src/squeezeplay_baby/share/applets/SqueezeboxBaby/* > ReduceBrightness-$PATCH_VERSION/ReduceBrightness-baby-$PATCH_VERSION.patch

	cd ReduceBrightness-$PATCH_VERSION
	sed 's/--- a\/src\/squeezeplay_baby\/share\//--- share\/jive\//g' ReduceBrightness-baby-$PATCH_VERSION.patch > ReduceBrightness-baby.patch.tmp
	mv ReduceBrightness-baby.patch.tmp ReduceBrightness-baby-$PATCH_VERSION.patch
	sed 's/+++ b\/src\/squeezeplay_baby\/share\//+++ share\/jive\//g' ReduceBrightness-baby-$PATCH_VERSION.patch > ReduceBrightness-baby.patch.tmp
	mv ReduceBrightness-baby.patch.tmp ReduceBrightness-baby-$PATCH_VERSION.patch

	CHECKSUM=`sha1sum ReduceBrightness-fab4-$PATCH_VERSION.patch | awk '{print $1}'`
	CHECKSUMBABY=`sha1sum ReduceBrightness-baby-$PATCH_VERSION.patch | awk '{print $1}'`

	# Copy base XML file to output directory
	cp ../repo-beta.xml repo-beta.xml
	
	# Replace placeholder with proper checksum
	sed 's/%CHECKSUM%/'${CHECKSUM}'/g' repo-beta.xml > repo-beta.xml.tmp
	mv repo-beta.xml.tmp repo-beta.xml
	sed 's/%CHECKSUMBABY%/'${CHECKSUMBABY}'/g' repo-beta.xml > repo-beta.xml.tmp
	mv repo-beta.xml.tmp repo-beta.xml
	
	# Replace placeholder with proper file name
	sed 's/%PATCH%/ReduceBrightness-fab4-'${PATCH_VERSION}'.patch/g' repo-beta.xml > repo-beta.xml.tmp
	mv repo-beta.xml.tmp repo-beta.xml
	sed 's/%PATCHBABY%/ReduceBrightness-baby-'${PATCH_VERSION}'.patch/g' repo-beta.xml > repo-beta.xml.tmp
	mv repo-beta.xml.tmp repo-beta.xml
	
	# Replace version info
	sed 's/%VERSION%/'${VERSION}'/g' repo-beta.xml > repo-beta.xml.tmp
	mv repo-beta.xml.tmp repo-beta.xml
	sed 's/%PATCH_VERSION%/'${PATCH_VERSION}'/g' repo-beta.xml > repo-beta.xml.tmp
	mv repo-beta.xml.tmp repo-beta.xml
	cd ..
fi

