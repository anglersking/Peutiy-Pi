docker rm -f h616_core_build
docker build  --network="host" -t h616_core_build . 
docker run -dit --net=host --hostname peutity-pi -v $(pwd)/out:/out -v /dev:/dev --privileged=true --name=h616_core_build h616_core_build