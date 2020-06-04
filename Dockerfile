FROM python:3-alpine

ADD entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash \
  && apk add --no-cache jq \
  && pip install awscli

ENTRYPOINT ["/entrypoint.sh"]
