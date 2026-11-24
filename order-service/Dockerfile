# Stage 1: Build the application
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /app

# Copy Maven configuration
COPY pom.xml .

# Download dependencies
RUN mvn -B dependency:go-offline

# Copy application source
COPY src ./src

# Build the application
RUN mvn -B package -DskipTests

# Stage 2: Run the application
FROM eclipse-temurin:21-jre

WORKDIR /app

# Copy generated JAR
COPY --from=build /app/target/order-service.jar app.jar

# Application port
EXPOSE 8082

# Start Spring Boot
ENTRYPOINT ["java", "-jar", "app.jar"]
