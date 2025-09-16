# syntax=docker/dockerfile:1.6
FROM quay.io/keycloak/keycloak:24.0.3 as builder

ENV KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true \
    KC_CACHE=ispn

WORKDIR /opt/keycloak
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:24.0.3

ENV KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true \
    KC_CACHE=ispn \
    KC_LOG_LEVEL=info \
    KC_CACHE_STACK=postgres

USER root
RUN microdnf update -y \
    && microdnf install -y curl \
    && microdnf clean all \
    && rm -rf /var/cache/yum
USER 1000

COPY --from=builder /opt/keycloak/ /opt/keycloak/

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start"]
