# Stage 1: Build the application
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B package -DskipTests

# Stage 2: Run the application
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
# hadolint ignore=DL3017
RUN apk upgrade --no-cache zlib && adduser -D -u 10001 app
COPY --from=build /app/target/order-service.jar app.jar
USER app
EXPOSE 8082
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8082/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
