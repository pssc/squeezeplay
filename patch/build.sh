#!/bin/sh

# Build squeezeplay_pssc patch for a specific Logitech Media Server (Squeezebox) version.
# Run ./build.sh to build for fab4 (Touch) and baby (Radio)
# Run ./build.sh fab4 to only build for fab4 (Touch)
# Run ./build.sh baby to only build for baby (Radio)

# LMS version to build for
VERSION="7.8"
# Original git version
ORIGINAL_GIT="49f41e4"
# Patch version
PATCH_VERSION=`git log --format="%H" -n 1 | cut -c 1-7`

# Build defaults
BUILD_FOR="fab4 baby"

if [ "$1" ]; then
	BUILD_FOR="$1"
fi

mkdir -p squeezeplay_pssc-$PATCH_VERSION
echo '*' > squeezeplay_pssc-$PATCH_VERSION/.gitignore

for TARGET in $BUILD_FOR
do
	echo "Building patch for $TARGET..."

	FILES="src/squeezeplay/share/* src/squeezeplay_$TARGET/share/*"

	cd ..
	FILES=`git diff $ORIGINAL_GIT --name-only $FILES`
	
	# Strip items in blacklist config file
	if [ -e "patch/blacklist_$TARGET.conf" ]; then
		for BLACKLIST_ITEM in `cat patch/blacklist_$TARGET.conf patch/blacklist.conf`
		do
			# Skip comment items
			if [ `echo "$BLACKLIST_ITEM" | cut -c 1` == "#" ]; then
				continue
			fi
			FILES=`echo "$FILES" | grep -v "$BLACKLIST_ITEM"`
		done
	fi

	git diff $ORIGINAL_GIT $FILES > patch/squeezeplay_pssc-$PATCH_VERSION/squeezeplay_pssc-$TARGET-$PATCH_VERSION.patch

	cd patch/squeezeplay_pssc-$PATCH_VERSION
	CHECKSUM=`shasum squeezeplay_pssc-$TARGET-$PATCH_VERSION.patch | awk '{print $1}'`
	
	# Read template XML
	PATCH_TEMPLATE=`cat ../patch-template.xml`

	# Replace placeholder with proper checksum
	PATCH_TEMPLATE=`echo "$PATCH_TEMPLATE" | sed 's/%CHECKSUM%/'${CHECKSUM}'/g'`
	
	# Replace placeholder with proper file name
	PATCH_TEMPLATE=`echo "$PATCH_TEMPLATE" | sed 's/%PATCH%/squeezeplay_pssc-'${TARGET}'-'${PATCH_VERSION}'.patch/g'`

	# Replace version info
	PATCH_TEMPLATE=`echo "$PATCH_TEMPLATE" | sed 's/%TARGET%/'${TARGET}'/g'`
	PATCH_TEMPLATE=`echo "$PATCH_TEMPLATE" | sed 's/%VERSION%/'${VERSION}'/g'`
	PATCH_TEMPLATE=`echo "$PATCH_TEMPLATE" | sed 's/%PATCH_VERSION%/'${PATCH_VERSION}'/g'`

	PATCH=`echo "$PATCH $PATCH_TEMPLATE"`

	cd ..
done

# Write the final repo.xml file
cat > squeezeplay_pssc-$PATCH_VERSION/repo.xml <<EOL
<?xml version="1.0"?>
<extensions>
	<details>
		<title lang="EN">Squeezeplay update by pssc</title>
	</details>
	<patches>
$PATCH
	</patches>
</extensions>
EOL
