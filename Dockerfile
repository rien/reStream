FROM debian:bullseye-slim
RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get -y install ffmpeg liblz4-tool pv ssh
RUN apt-get clean
RUN mkdir -p /root/.ssh
RUN echo "StrictHostKeyChecking no" > /root/.ssh/config
COPY reStream.sh /
ENTRYPOINT ["/reStream.sh"]
