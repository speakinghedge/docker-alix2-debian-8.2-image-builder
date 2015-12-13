#/bin/sh

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
DOCKER_BUILDER_IMAGE="debian_jessie_alix_image_builder:0.1"

if [ $(docker history -q ${DOCKER_BUILDER_IMAGE} 2>/dev/null | wc -l) -eq 0 ] ; then
	docker build -t ${DOCKER_BUILDER_IMAGE} ${SCRIPTPATH}/docker/
fi

docker run --privileged -i -v "${SCRIPTPATH}":/var/alix_image_builder/ -t ${DOCKER_BUILDER_IMAGE} /bin/sh _alix_image_recipe.sh
