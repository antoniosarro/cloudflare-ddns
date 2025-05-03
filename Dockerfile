FROM alpine:3.21

RUN apk update && \
    apk add --no-cache \
    bash \
    curl \
    jq \
    coreutils \
    grep \
    gawk \
    tzdata \
    && \
    rm -rf /var/cache/apk/*

ENV TZ=Europe/Rome
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY cloudflare_ddns.sh /usr/local/bin/cloudflare_ddns.sh

RUN chmod +x /usr/local/bin/cloudflare_ddns.sh

RUN echo "*/30 * * * * /usr/local/bin/cloudflare_ddns.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

RUN chmod 0600 /etc/crontabs/root && \
    chown root:root /etc/crontabs/root

RUN touch /var/log/cron.log && chmod 600 /var/log/cron.log

CMD ["crond", "-f"]

#  Optionally, define a volume to persist logs
#  VOLUME /var/log/cron.log