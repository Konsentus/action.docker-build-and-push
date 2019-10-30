FROM docker:latest

ADD entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash \
  && apk add --no-cache python3 \
  && pip3 install awscli

ENTRYPOINT ["/entrypoint.sh"]
