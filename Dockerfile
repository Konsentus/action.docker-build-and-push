FROM docker:latest

ADD entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash \
  && apk add --no-cache python3 \
  && apk add --no-cache py3-pip \
  && apk add --no-cache jq \
  && apk add --no-cache aws-cli

ENTRYPOINT ["/entrypoint.sh"]
