# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Runtime image. The bootJar is built on the CI runner (Gradle with a warm
# cache) and copied in, so the image layer stays small and reproducible.
# ---------------------------------------------------------------------------
FROM docker.io/library/eclipse-temurin:21-jre-jammy

# Drop root: the JVM never needs privileged capabilities here.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && mkdir -p /app \
    && chown -R app:app /app \
    && apt-get update \
    && apt-get install --no-install-recommends -y curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --chown=app:app build/libs/*.jar /app/application.jar

USER app

EXPOSE 8080

ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseContainerSupport -Djava.security.egd=file:/dev/./urandom"

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
    CMD curl --fail --silent http://127.0.0.1:8080/actuator/health || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/application.jar"]
