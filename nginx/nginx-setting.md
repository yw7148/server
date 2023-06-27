# Docker를 이용한 nginx 배포
## network 만들기
docker network create youngwon

docker run -d -p 80:80 -v /home/ec2-user/server/nginx/nginx.conf:/etc/nginx/nginx.conf --network youngwon --name nginx nginx:latest